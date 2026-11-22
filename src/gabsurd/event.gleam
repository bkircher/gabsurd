//// Event operations for the Absurd durable workflow system.
//// Provides functions for emitting and awaiting events.

import gabsurd/client.{type Db, type GabsurdError}
import gabsurd/internal/query
import gabsurd/internal/sql
import gabsurd/task.{type RunId, type TaskId, RunId, TaskId}
import gleam/bool
import gleam/json
import gleam/option
import gleam/result

/// Result of an event wait.
pub type AwaitResult {
  /// The event arrived. Its payload is JSON text and can be `"null"`.
  Received(payload: String)
  /// The run is asleep until the event arrives or the deadline passes.
  Suspended
  /// The deadline passed before the event arrived.
  TimedOut
}

/// Emit an event to a queue.
pub fn emit(
  db db: Db,
  queue_name queue_name: String,
  event_name event_name: String,
  payload payload: json.Json,
) -> Result(Nil, GabsurdError) {
  sql.emit_event(client.connection(db), queue_name, event_name, payload)
  |> query.exec
}

/// Await an event for a task step. Use a stable, unique step name.
/// The run must belong to the given task.
/// The `$await:` and `$await-` prefixes are for SDK checkpoints.
/// `None` sets no deadline. A timeout in `Some` is in seconds. `Some(0)`
/// makes the suspended run ready to claim again immediately if the event
/// is missing.
///
/// Use `task.claim` to claim the run. It saves any timeout for this step so
/// a late event cannot change the outcome.
///
/// This function does not check the claim owner or expiry. In a worker
/// handler, use `context.await_event` instead.
pub fn await(
  db db: Db,
  queue_name queue_name: String,
  task_id task_id: TaskId,
  run_id run_id: RunId,
  step_name step_name: String,
  event_name event_name: String,
  timeout timeout: option.Option(Int),
) -> Result(AwaitResult, GabsurdError) {
  let TaskId(task_uuid) = task_id
  let RunId(run_uuid) = run_id
  let connection = client.connection(db)
  use #(should_suspend, payload) <- result.try(case timeout {
    option.Some(seconds) ->
      sql.await_event(
        connection,
        queue_name,
        task_uuid,
        run_uuid,
        step_name,
        event_name,
        seconds,
      )
      |> query.one
      |> result.map(fn(row) { #(row.should_suspend, row.payload) })
    option.None ->
      sql.await_event_unlimited(
        connection,
        queue_name,
        task_uuid,
        run_uuid,
        step_name,
        event_name,
      )
      |> query.one
      |> result.map(fn(row) { #(row.should_suspend, row.payload) })
  })
  await_result(should_suspend, payload)
}

@internal
pub fn await_if_claimed(
  db db: Db,
  queue_name queue_name: String,
  run_id run_id: RunId,
  owner owner: String,
  step_name step_name: String,
  event_name event_name: String,
  timeout timeout: option.Option(Int),
) -> Result(AwaitResult, GabsurdError) {
  let RunId(run_uuid) = run_id
  let connection = client.connection(db)
  use #(claim_lost, should_suspend, payload) <- result.try(case timeout {
    option.Some(seconds) ->
      sql.await_event_if_claimed(
        connection,
        queue_name,
        run_uuid,
        owner,
        step_name,
        event_name,
        seconds,
      )
      |> query.one
      |> result.map(fn(row) {
        #(row.claim_lost, row.should_suspend, row.payload)
      })
    option.None ->
      sql.await_event_unlimited_if_claimed(
        connection,
        queue_name,
        run_uuid,
        owner,
        step_name,
        event_name,
      )
      |> query.one
      |> result.map(fn(row) {
        #(row.claim_lost, row.should_suspend, row.payload)
      })
  })
  use <- bool.guard(when: claim_lost, return: Error(client.ClaimLost))
  await_result(should_suspend, payload)
}

fn await_result(
  should_suspend: Bool,
  payload: option.Option(String),
) -> Result(AwaitResult, GabsurdError) {
  case should_suspend, payload {
    True, option.None -> Ok(Suspended)
    False, option.Some(payload) -> Ok(Received(payload))
    False, option.None -> Ok(TimedOut)
    True, option.Some(_) ->
      Error(client.QueryError("event wait returned a payload while suspended"))
  }
}
