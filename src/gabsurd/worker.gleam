//// OTP worker for the Absurd durable workflow system.
//// The polling actor claims only as many tasks as it can start.
//// Each task runs in a separate linked process. The actor handles its exit
//// so a handler panic does not stop the worker.
//// An unlinked process kills the task if the worker exits first, even if
//// the handler traps exits.
////
//// ## Distributed systems behaviour
////
//// - **Claim extension**: `context.set_checkpoint` and `context.heartbeat`
////   extend the lease only while the handler owns an active claim. Send a
////   heartbeat before the lease expires during long operations.
//// - **Claim expiry**: The worker checks leases even when all slots are full.
////   It stops an expired handler and frees the slot when the process exits.
////   Absurd records the timeout and applies the retry policy on a claim poll.
//// - **Error backoff**: The worker increases the delay after a claim or
////   lease check fails, up to `max_backoff` (default 60s). It resets the delay
////   when the operation succeeds.
//// - **Unknown task deferral**: Tasks with no registered handler are deferred
////   (rescheduled with a delay) rather than failed. This supports rolling
////   deployments where a new task type may arrive before its handler is
////   deployed.
//// - **Claim ownership**: The worker records results and crashes or defers
////   unknown tasks only while the claim is still active and owned by this worker.

import gabsurd/client.{
  type Db, type GabsurdError, ClaimLost, RunAlreadyFailed, TaskCancelled,
}
import gabsurd/context.{type Context}
import gabsurd/internal/query
import gabsurd/internal/sql
import gabsurd/lease.{type ClaimExpiry}
import gabsurd/task.{type RunId}
import gleam/bool
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/set
import youid/uuid

// ============================================================================
// Public Types
// ============================================================================

/// The result of a handler's `execute` function.
///
/// Return `Complete(result)` to mark the task as successfully done.
/// Return `Fail(reason)` to mark the task as failed.
/// Return `Suspend` when a workflow operation puts the run to sleep.
/// Return `Cancelled` when the database reports that the task was cancelled.
/// Neither outcome calls complete or fail. `Cancelled` does not cancel a task.
pub type HandlerResult {
  Complete(json.Json)
  Fail(json.Json)
  Suspend
  Cancelled
}

/// A handler for a specific task type.
///
/// Define one of these for each kind of task your workers should process.
/// The worker dispatches claimed tasks to the handler matching their `task_name`.
///
/// ## Example
///
/// ```gleam
/// let email_handler = worker.Handler(
///   task_name: "send_email",
///   execute: fn(ctx) {
///     // ... send email using ctx.params(ctx) ...
///     Complete(json.object([#("sent", json.bool(True))]))
///   },
///   on_error: option.None,
/// )
/// ```
pub type Handler {
  Handler(
    /// The task_name this handler responds to.
    task_name: String,
    /// Execute the task. Receives a `Context` with the claim details,
    /// database connection, and helper methods. Return `Complete`,
    /// `Fail`, `Suspend`, or `Cancelled`.
    execute: fn(Context) -> HandlerResult,
    /// Optional hook called when execute returns Fail.
    /// Receives the context and the error json. Use for logging/metrics.
    on_error: option.Option(fn(Context, json.Json) -> Nil),
  )
}

/// A checked delay in milliseconds for a worker timer.
pub opaque type DelayMs {
  DelayMs(milliseconds: Int)
}

/// The delay is outside the range accepted by `delay_ms`.
pub type DelayError {
  DelayOutOfRange
}

/// Worker configuration. Create with `new()` and customize with `with_*` functions.
pub opaque type Config {
  Config(
    db: Db,
    queue_name: String,
    worker_id: String,
    poll_interval: DelayMs,
    claim_expiry: ClaimExpiry,
    batch_size: Int,
    max_backoff: DelayMs,
    handlers: List(Handler),
  )
}

/// A running worker handle.
pub opaque type Worker {
  Worker(pid: process.Pid, subject: process.Subject(Message))
}

/// The worker did not confirm a graceful shutdown.
pub type ShutdownError {
  ShutdownTimedOut
  WorkerExited(process.ExitReason)
}

type Message {
  Poll
  CheckLeases(delay: DelayMs)
  Shutdown
  LinkedExit(process.ExitMessage)
}

type PollTiming {
  Immediate
  Delayed
}

// ============================================================================
// Internal State
// ============================================================================

type ActiveClaim {
  ActiveClaim(run_id: RunId, owner: String, timed_out: Bool)
}

type WorkerState {
  WorkerState(
    config: Config,
    handler_map: dict.Dict(String, Handler),
    subject: process.Subject(Message),
    parent: process.Pid,
    active: dict.Dict(process.Pid, ActiveClaim),
    stopping: option.Option(process.ExitReason),
    // A delayed or queued Poll stays pending until the worker receives it.
    poll_pending: Bool,
    lease_check_pending: Bool,
    retry_delay: DelayMs,
  )
}

// ============================================================================
// Configuration
// ============================================================================

// Use the portable 32-bit timer range. Recent OTP versions can accept
// longer delays, but their limit depends on the runtime's monotonic clock.
const max_delay_ms = 4_294_967_295

/// Check that a worker timer delay is between 1 and 4,294,967,295 ms.
/// Zero would let the worker poll again without a delay.
pub fn delay_ms(milliseconds: Int) -> Result(DelayMs, DelayError) {
  use <- bool.guard(
    when: milliseconds < 1 || milliseconds > max_delay_ms,
    return: Error(DelayOutOfRange),
  )
  Ok(DelayMs(milliseconds))
}

/// Create a new worker config with defaults.
pub fn new(
  db db: Db,
  queue_name queue_name: String,
  handlers handlers: List(Handler),
) -> Config {
  Config(
    db: db,
    queue_name: queue_name,
    worker_id: "gabsurd_worker",
    poll_interval: DelayMs(5000),
    claim_expiry: lease.default_expiry,
    batch_size: 1,
    max_backoff: DelayMs(60_000),
    handlers: handlers,
  )
}

// nolint: unused_exports -- public API for callers that set a worker ID prefix
/// Set the worker ID prefix. Each claim batch adds a unique suffix.
pub fn with_worker_id(
  config config: Config,
  worker_id worker_id: String,
) -> Config {
  Config(..config, worker_id: worker_id)
}

/// Set the poll interval. Use `delay_ms` to check the interval first.
pub fn with_poll_interval(
  config config: Config,
  interval interval: DelayMs,
) -> Config {
  Config(..config, poll_interval: interval)
}

/// Set claim expiry. Use `lease.NoExpiry` to disable recovery by lease expiry.
/// The default lease expires after 30 seconds.
pub fn with_claim_expiry(
  config config: Config,
  expiry expiry: ClaimExpiry,
) -> Config {
  Config(..config, claim_expiry: expiry)
}

/// Set the maximum number of tasks this worker can execute at the same time.
/// Each poll claims work only for free slots. The minimum capacity is one.
pub fn with_batch_size(config config: Config, size size: Int) -> Config {
  Config(..config, batch_size: size)
}

// nolint: unused_exports -- public API for callers that set a backoff limit
/// Set the maximum backoff after claim or lease check errors.
/// Use `delay_ms` to check the delay first. The default is 60 seconds.
pub fn with_max_backoff(config config: Config, delay delay: DelayMs) -> Config {
  Config(..config, max_backoff: delay)
}

// ============================================================================
// Lifecycle
// ============================================================================

/// Start a worker linked to the calling process. The worker drains active
/// tasks when its parent exits, subject to the supervisor shutdown timeout.
pub fn start(config: Config) -> actor.StartResult(Worker) {
  let handler_map =
    config.handlers
    |> list.map(fn(h) { #(h.task_name, h) })
    |> dict.from_list()

  let parent = process.self()
  let init = fn(subject: process.Subject(Message)) {
    // Trap exits from the parent and from the task processes.
    process.trap_exits(True)
    let state =
      WorkerState(
        config:,
        handler_map:,
        subject:,
        parent:,
        active: dict.new(),
        stopping: option.None,
        poll_pending: False,
        lease_check_pending: False,
        retry_delay: config.poll_interval,
      )
    schedule_poll(state, Delayed)
    |> actor.initialised
    |> actor.selecting(
      process.new_selector()
      |> process.select(subject)
      |> process.select_trapped_exits(LinkedExit),
    )
    |> actor.returning(Worker(pid: process.self(), subject:))
    |> Ok
  }

  actor.new_with_initialiser(5000, init)
  |> actor.on_message(handle_message)
  |> actor.start()
}

// nolint: unused_exports -- public API for callers that do not wait for shutdown
/// Ask the worker to stop claiming tasks and let active tasks finish.
/// Use `stop_and_wait` to wait for confirmation.
pub fn stop(worker: Worker) -> Nil {
  process.send(worker.subject, Shutdown)
}

/// Request shutdown and wait for active tasks to finish and the worker to exit.
/// A timeout does not kill the worker. If it already exited, this cannot
/// confirm how it stopped and returns `WorkerExited`.
pub fn stop_and_wait(
  worker worker: Worker,
  timeout_ms timeout_ms: Int,
) -> Result(Nil, ShutdownError) {
  let monitor = process.monitor(worker.pid)
  stop(worker)
  let outcome =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down.reason })
    |> process.selector_receive(timeout_ms)
  process.demonitor_process(monitor)
  case outcome {
    Ok(process.Normal) -> Ok(Nil)
    Ok(reason) -> Error(WorkerExited(reason))
    Error(Nil) -> Error(ShutdownTimedOut)
  }
}

/// Create a child spec for adding to a static_supervisor.
pub fn child_spec(config: Config) -> supervision.ChildSpecification(Worker) {
  supervision.worker(fn() { start(config) })
}

/// Create a list of child specs for a worker pool (N workers).
/// Each worker gets a unique worker_id incorporating a unique integer
/// to avoid collisions between pools.
pub fn pool_child_specs(
  name name: String,
  config config: Config,
  count count: Int,
) -> List(supervision.ChildSpecification(Worker)) {
  let prefix = name <> "_" <> int.to_string(client.unique_integer()) <> "_"
  int.range(from: 1, to: int.max(0, count) + 1, with: [], run: fn(specs, index) {
    // Prepend each spec to keep the highest worker index first.
    let worker_id = prefix <> int.to_string(index)
    [child_spec(Config(..config, worker_id:)), ..specs]
  })
}

// ============================================================================
// Message Handler
// ============================================================================

fn handle_message(
  state: WorkerState,
  message: Message,
) -> actor.Next(WorkerState, Message) {
  case message, state.stopping {
    Poll, _ -> handle_poll(state) |> actor.continue
    CheckLeases(delay), _ -> handle_lease_check(state, delay) |> actor.continue
    Shutdown, option.None ->
      finish_or_wait(
        WorkerState(..state, stopping: option.Some(process.Normal)),
      )
    Shutdown, option.Some(_) -> actor.continue(state)
    LinkedExit(exit), _ -> handle_exit(state, exit)
  }
}

fn handle_poll(state: WorkerState) -> WorkerState {
  let cleared = WorkerState(..state, poll_pending: False)
  case state.stopping, state.poll_pending, free_slots(state) {
    option.None, True, slots if slots > 0 ->
      poll(cleared, slots) |> schedule_poll(Delayed)
    _, _, _ -> cleared
  }
}

fn schedule_poll(state: WorkerState, timing: PollTiming) -> WorkerState {
  case state.stopping, state.poll_pending, free_slots(state) {
    option.None, False, slots if slots > 0 -> {
      case timing {
        Immediate -> process.send(state.subject, Poll)
        Delayed -> {
          let _timer =
            process.send_after(
              state.subject,
              state.retry_delay.milliseconds,
              Poll,
            )
          Nil
        }
      }
      WorkerState(..state, poll_pending: True)
    }
    _, _, _ -> state
  }
}

fn free_slots(state: WorkerState) -> Int {
  int.max(1, state.config.batch_size) - dict.size(state.active)
}

// A pending lease check must not delay a claim poll when a slot opens.
fn schedule_lease_check(state: WorkerState, delay: DelayMs) -> WorkerState {
  let should_check =
    state.config.claim_expiry != lease.NoExpiry
    && list.any(dict.values(state.active), fn(claim) { !claim.timed_out })
  case state.lease_check_pending, should_check {
    False, True -> {
      let _timer =
        process.send_after(
          state.subject,
          delay.milliseconds,
          CheckLeases(delay),
        )
      WorkerState(..state, lease_check_pending: True)
    }
    _, _ -> state
  }
}

fn handle_lease_check(state: WorkerState, delay: DelayMs) -> WorkerState {
  let cleared = WorkerState(..state, lease_check_pending: False)
  case check_leases(cleared) {
    Ok(checked) -> schedule_lease_check(checked, state.config.poll_interval)
    Error(error) -> {
      log_error("check leases", error)
      schedule_lease_check(cleared, backoff_delay(state.config, delay))
    }
  }
}

fn check_leases(state: WorkerState) -> Result(WorkerState, GabsurdError) {
  let config = state.config
  let claims =
    dict.values(state.active)
    |> list.filter_map(fn(claim) {
      case claim {
        ActiveClaim(task.RunId(run_id), owner, False) -> Ok(#(run_id, owner))
        ActiveClaim(_, _, True) -> Error(Nil)
      }
    })
  case claims {
    [] -> Ok(state)
    _ -> {
      let #(run_ids, owners) = list.unzip(claims)
      use expired <- result.map(
        sql.expired_claims(
          client.connection(config.db),
          config.queue_name,
          run_ids,
          owners,
        )
        |> query.many,
      )
      case expired {
        [] -> state
        _ -> stop_expired_handlers(state, expired)
      }
    }
  }
}

fn stop_expired_handlers(
  state: WorkerState,
  expired: List(sql.ExpiredClaimsRow),
) -> WorkerState {
  let expired =
    expired
    |> list.map(fn(row) { #(task.RunId(row.run_id), row.claim_owner) })
    |> set.from_list
  let active =
    dict.map_values(state.active, fn(pid, claim) {
      case
        !claim.timed_out && set.contains(expired, #(claim.run_id, claim.owner))
      {
        True -> {
          process.kill(pid)
          // Keep the slot in use until the worker receives the exit.
          ActiveClaim(..claim, timed_out: True)
        }
        False -> claim
      }
    })
  WorkerState(..state, active:)
}

fn poll(state: WorkerState, slots: Int) -> WorkerState {
  let config = state.config
  let handler_map = state.handler_map
  // The run ID can stay the same across claims. The owner ID must change.
  let owner = config.worker_id <> "/" <> uuid.v4_string()
  case
    task.claim(config.db, config.queue_name, owner, config.claim_expiry, slots)
  {
    Ok(claims) -> {
      let active =
        list.fold(claims, state.active, fn(active, claim) {
          let active_claim = ActiveClaim(claim.run_id, owner, timed_out: False)
          let pid = spawn_task(config:, handler_map:, claim:, active_claim:)
          dict.insert(active, pid, active_claim)
        })
      WorkerState(..state, active:, retry_delay: config.poll_interval)
      |> schedule_lease_check(config.poll_interval)
    }
    Error(error) -> {
      log_error("claim", error)
      WorkerState(
        ..state,
        retry_delay: backoff_delay(config, state.retry_delay),
      )
    }
  }
}

fn backoff_delay(config: Config, previous_delay: DelayMs) -> DelayMs {
  DelayMs(int.min(
    previous_delay.milliseconds * 2,
    config.max_backoff.milliseconds,
  ))
}

fn handle_exit(
  state: WorkerState,
  exit: process.ExitMessage,
) -> actor.Next(WorkerState, Message) {
  case dict.get(state.active, exit.pid) {
    Ok(claim) -> {
      case exit.reason, claim.timed_out {
        process.Normal, _ | _, True -> Nil
        _, False -> record_handler_crash(state.config, claim)
      }
      WorkerState(..state, active: dict.delete(state.active, exit.pid))
      |> schedule_poll(Immediate)
      |> finish_or_wait
    }
    Error(Nil) if exit.pid == state.parent || exit.reason != process.Normal ->
      finish_or_wait(WorkerState(..state, stopping: option.Some(exit.reason)))
    Error(Nil) -> actor.continue(state)
  }
}

fn record_handler_crash(config: Config, claim: ActiveClaim) -> Nil {
  let reason =
    json.object([
      #("name", json.string("$HandlerCrash")),
      #("message", json.string("Task process exited before finishing")),
    ])
  fail_claim(config:, claim:, reason:)
  |> handle_run_result("record handler crash", _)
}

fn finish_or_wait(state: WorkerState) -> actor.Next(WorkerState, Message) {
  case dict.is_empty(state.active), state.stopping {
    True, option.Some(process.Normal) -> actor.stop()
    True, option.Some(process.Abnormal(reason)) -> {
      // Preserve the exit reason, for example OTP's shutdown signal.
      process.trap_exits(False)
      process.send_abnormal_exit(process.self(), reason)
      actor.stop()
    }
    True, option.Some(process.Killed) -> {
      process.kill(process.self())
      actor.stop()
    }
    _, _ -> actor.continue(state)
  }
}

// ============================================================================
// Task Execution
// ============================================================================

fn spawn_task(
  config config: Config,
  handler_map handler_map: dict.Dict(String, Handler),
  claim claim: task.Claim,
  active_claim active_claim: ActiveClaim,
) -> process.Pid {
  let worker_pid = process.self()
  process.spawn(fn() {
    let task_pid = process.self()
    // Start the watcher before the handler can trap linked exits.
    let _watcher =
      process.spawn_unlinked(fn() { watch_task(worker_pid, task_pid) })
    execute_task(config:, handler_map:, claim:, active_claim:)
  })
}

fn watch_task(worker_pid: process.Pid, task_pid: process.Pid) -> Nil {
  let worker_monitor = process.monitor(worker_pid)
  let task_monitor = process.monitor(task_pid)
  process.new_selector()
  |> process.select_specific_monitor(worker_monitor, fn(_) {
    process.kill(task_pid)
  })
  |> process.select_specific_monitor(task_monitor, fn(_) { Nil })
  |> process.selector_receive_forever
}

fn execute_task(
  config config: Config,
  handler_map handler_map: dict.Dict(String, Handler),
  claim claim: task.Claim,
  active_claim active_claim: ActiveClaim,
) -> Nil {
  case dict.get(handler_map, claim.task_name) {
    Ok(handler) -> execute_handler(config:, claim:, active_claim:, handler:)
    Error(Nil) -> {
      // Defer unknown tasks until a worker with the new handler can claim them.
      case defer_claim(config:, claim: active_claim) {
        Ok(Nil) ->
          io.println_error(
            "gabsurd worker: deferred unknown task \""
            <> claim.task_name
            <> "\" (no handler registered)",
          )
        outcome -> handle_run_result("defer unknown task", outcome)
      }
    }
  }
}

fn defer_claim(
  config config: Config,
  claim claim: ActiveClaim,
) -> Result(Nil, GabsurdError) {
  let task.RunId(run_uuid) = claim.run_id
  sql.schedule_run_if_claimed(
    client.connection(config.db),
    config.queue_name,
    run_uuid,
    claim.owner,
    60,
  )
  |> query.claim_write(fn(row) { row.scheduled })
}

fn execute_handler(
  config config: Config,
  claim claim: task.Claim,
  active_claim active_claim: ActiveClaim,
  handler handler: Handler,
) -> Nil {
  let Config(db:, queue_name:, claim_expiry:, ..) = config
  let ctx =
    context.Context(
      db:,
      queue_name:,
      claim:,
      claim_owner: active_claim.owner,
      claim_expiry:,
    )
  case handler.execute(ctx) {
    Complete(result_json) ->
      complete_claim(config:, claim: active_claim, state: result_json)
      |> handle_run_result("complete", _)
    Fail(error_json) -> {
      case handler.on_error {
        option.Some(hook) -> hook(ctx, error_json)
        option.None -> Nil
      }
      fail_claim(config:, claim: active_claim, reason: error_json)
      |> handle_run_result("fail", _)
    }
    Suspend | Cancelled -> Nil
  }
}

fn complete_claim(
  config config: Config,
  claim claim: ActiveClaim,
  state state: json.Json,
) -> Result(Nil, GabsurdError) {
  let task.RunId(run_uuid) = claim.run_id
  sql.complete_run_if_claimed(
    client.connection(config.db),
    config.queue_name,
    run_uuid,
    claim.owner,
    state,
  )
  |> query.claim_write(fn(row) { row.completed })
}

fn fail_claim(
  config config: Config,
  claim claim: ActiveClaim,
  reason reason: json.Json,
) -> Result(Nil, GabsurdError) {
  let task.RunId(run_uuid) = claim.run_id
  sql.fail_run_if_claimed(
    client.connection(config.db),
    config.queue_name,
    run_uuid,
    claim.owner,
    reason,
  )
  |> query.claim_write(fn(row) { row.failed })
}

fn handle_run_result(
  action: String,
  outcome: Result(Nil, GabsurdError),
) -> Nil {
  case outcome {
    Ok(Nil)
    | Error(ClaimLost)
    | Error(TaskCancelled)
    | Error(RunAlreadyFailed(_)) -> Nil
    Error(error) -> log_error(action, error)
  }
}

fn log_error(action: String, error: GabsurdError) -> Nil {
  io.println_error(
    "gabsurd worker: " <> action <> ": " <> client.error_message(error),
  )
}
