//// Execution context for a running task.
////
//// Constructed by the worker and passed to your handler. Encapsulates
//// the database connection, queue, claim details, and claim expiry so
//// you don't have to pass them around. Provides high-level operations
//// for idempotent steps, checkpoints, heartbeats, and event coordination.
////
//// ## Example
////
//// ```gleam
//// let handler = Handler(
////   task_name: "process_order",
////   execute: fn(ctx) {
////     case order_workflow(ctx) {
////       Ok(Nil) -> Complete(json.object([#("status", json.string("done"))]))
////       Error(client.TaskCancelled) -> worker.Cancelled
////       Error(e) -> Fail(encode_error(e))
////     }
////   },
////   on_error: option.None,
//// )
////
//// fn order_workflow(ctx) -> Result(Nil, GabsurdError) {
////   use _ <- result.try(context.step(ctx, "charge", decode.success(Nil), fn() {
////     charge_card(decode_params(context.params(ctx)))
////     json.null()
////   }))
////   use _ <- result.try(context.step(ctx, "reserve", decode.success(Nil), fn() {
////     reserve_inventory(decode_params(context.params(ctx)))
////     json.null()
////   }))
////   Ok(Nil)
//// }
//// ```

import gabsurd/checkpoint
import gabsurd/client.{type Db, type GabsurdError}
import gabsurd/event
import gabsurd/internal/query
import gabsurd/internal/sql
import gabsurd/lease.{type ClaimExpiry}
import gabsurd/task.{type Claim, type RunId, type TaskId, RunId}
import gleam/dynamic/decode
import gleam/function
import gleam/json
import gleam/option
import gleam/result

// ============================================================================
// Public Types
// ============================================================================

/// Execution context for a running task. Constructed by the worker,
/// passed to your handler.
pub type Context {
  Context(
    db: Db,
    queue_name: String,
    claim: Claim,
    /// The unique owner string passed to `task.claim`.
    claim_owner: String,
    claim_expiry: ClaimExpiry,
  )
}

/// An error from a fallible step.
pub type StepError(e) {
  /// The step callback returned an application error.
  StepFailed(e)
  /// The SDK could not read, decode, or save the checkpoint.
  StepSdkError(GabsurdError)
}

// ============================================================================
// Accessors
// ============================================================================

/// The task's unique identifier.
pub fn task_id(ctx: Context) -> TaskId {
  ctx.claim.task_id
}

/// The current run's unique identifier.
pub fn run_id(ctx: Context) -> RunId {
  ctx.claim.run_id
}

/// The task parameters as a raw JSON string.
pub fn params(ctx: Context) -> String {
  ctx.claim.params
}

/// The task name.
pub fn task_name(ctx: Context) -> String {
  ctx.claim.task_name
}

/// The current attempt number (1-based).
pub fn attempt(ctx: Context) -> Int {
  ctx.claim.attempt
}

// nolint: unused_exports -- public API for handlers that need the claim expiry
/// The lease duration, or `lease.NoExpiry` if the claim has no deadline.
pub fn claim_expiry(ctx: Context) -> ClaimExpiry {
  ctx.claim_expiry
}

// ============================================================================
// Idempotent Steps
// ============================================================================

/// Run a step and save its result under a stable, unique name.
///
/// Use a different name for each operation. In a loop, add a stable item key
/// to the name. The `$await:` and `$await-` prefixes are for event waits.
///
/// If a checkpoint with this name exists, decode the saved value and skip
/// `run`. A checkpoint without JSON state returns an error.
/// If there is no checkpoint, run the callback, decode its result, and save it.
/// If decoding fails, return a `CheckpointDecodeError` without saving it.
/// Saving a checkpoint renews an active lease for its configured duration.
/// A claim without a deadline stays without a deadline.
/// The save fails if the claim expires or changes owner.
/// Use `try_step` if the callback can return an error.
///
/// The `decoder` parameter is required because Gleam's `json.Json` type is
/// write-only — values loaded from the database must be parsed with an
/// explicit decoder. For steps that don't need a return value, use
/// `decode.success(Nil)`.
///
/// ## Example
///
/// ```gleam
/// // Step that returns a value:
/// use charge_id <- result.try(
///   context.step(ctx, "charge", charge_id_decoder(), fn() {
///     let result = charge_card(...)
///     json.object([#("charge_id", json.string(result.id))])
///   }),
/// )
///
/// // Step that doesn't return a value:
/// use _ <- result.try(context.step(ctx, "notify", decode.success(Nil), fn() {
///   send_email(...)
///   json.null()
/// }))
/// ```
pub fn step(
  ctx: Context,
  name: String,
  decoder: decode.Decoder(a),
  run: fn() -> json.Json,
) -> Result(a, GabsurdError) {
  run_step(ctx, name, decoder, fn() { Ok(run()) }, function.identity)
}

/// Like `step`, but the callback can return an application error.
/// When the callback returns `Error(e)`, return `StepFailed(e)` and do not
/// save a checkpoint. Read, decode, and save errors return `StepSdkError`.
pub fn try_step(
  ctx: Context,
  name: String,
  decoder: decode.Decoder(a),
  run: fn() -> Result(json.Json, e),
) -> Result(a, StepError(e)) {
  run_step(
    ctx,
    name,
    decoder,
    fn() { run() |> result.map_error(StepFailed) },
    StepSdkError,
  )
}

fn run_step(
  ctx: Context,
  name: String,
  decoder: decode.Decoder(a),
  run: fn() -> Result(json.Json, e),
  sdk_error: fn(GabsurdError) -> e,
) -> Result(a, e) {
  let parse = fn(payload) {
    json.parse(payload, decoder)
    |> result.map_error(fn(error) {
      sdk_error(client.CheckpointDecodeError(error))
    })
  }
  use saved <- result.try(
    read_checkpoint(ctx, name) |> result.map_error(sdk_error),
  )
  case saved {
    option.Some(checkpoint.Checkpoint(state: option.Some(payload), ..)) ->
      parse(payload)
    option.Some(_) ->
      Error(
        sdk_error(client.QueryError("checkpoint has no saved state: " <> name)),
      )
    option.None -> {
      use state <- result.try(run())
      use value <- result.try(parse(json.to_string(state)))
      use _ <- result.try(
        set_checkpoint(ctx:, name:, state:) |> result.map_error(sdk_error),
      )
      Ok(value)
    }
  }
}

// ============================================================================
// Low-level Checkpoint Access
// ============================================================================

/// Get a checkpoint's raw JSON state string.
/// Returns `Ok(None)` if the checkpoint does not exist or its state is SQL NULL.
pub fn get_checkpoint(
  ctx ctx: Context,
  name name: String,
) -> Result(option.Option(String), GabsurdError) {
  read_checkpoint(ctx, name)
  |> result.map(fn(saved) { option.then(saved, fn(cp) { cp.state }) })
}

fn read_checkpoint(
  ctx: Context,
  name: String,
) -> Result(option.Option(checkpoint.Checkpoint), GabsurdError) {
  checkpoint.get(ctx.db, ctx.queue_name, ctx.claim.task_id, name, False)
}

/// Set a checkpoint and extend the lease if this context still owns the claim.
pub fn set_checkpoint(
  ctx ctx: Context,
  name name: String,
  state state: json.Json,
) -> Result(Nil, GabsurdError) {
  let RunId(run_uuid) = ctx.claim.run_id
  sql.set_checkpoint_if_claimed(
    client.connection(ctx.db),
    ctx.queue_name,
    run_uuid,
    ctx.claim_owner,
    name,
    state,
    lease.to_sql_seconds(ctx.claim_expiry),
  )
  |> query.claim_write(fn(row) { row.saved })
}

// ============================================================================
// Lease Management
// ============================================================================

/// Renew an active lease if this context still owns the claim.
/// If the claim has no deadline, check ownership without setting a deadline.
pub fn heartbeat(ctx: Context) -> Result(Nil, GabsurdError) {
  let RunId(run_uuid) = ctx.claim.run_id
  sql.extend_claim_if_claimed(
    client.connection(ctx.db),
    ctx.queue_name,
    run_uuid,
    ctx.claim_owner,
    lease.to_sql_seconds(ctx.claim_expiry),
  )
  |> query.claim_write(fn(row) { row.extended })
}

// ============================================================================
// Event Coordination
// ============================================================================

/// Await an external event with an optional timeout in seconds.
/// Use `None` to wait without a deadline or `Some(seconds)` to set one.
/// If the event is not available, the run sleeps and this function returns
/// `event.Suspended`. Return `worker.Suspend` from the handler to release
/// its slot. On resume this returns `event.Received(payload)` or
/// `event.TimedOut`.
/// The claim saves the timeout before the handler starts. On later claims,
/// this function returns the saved timeout even if the event arrives late.
/// A wait can change database state only while this context owns an
/// active claim. If the claim is lost, the write returns `ClaimLost` unless
/// the task was cancelled or the run already failed.
pub fn await_event(
  ctx ctx: Context,
  event_name event_name: String,
  timeout timeout: option.Option(Int),
) -> Result(event.AwaitResult, GabsurdError) {
  event.await_if_claimed(
    ctx.db,
    ctx.queue_name,
    ctx.claim.run_id,
    ctx.claim_owner,
    "$await:" <> event_name,
    event_name,
    timeout,
  )
}
