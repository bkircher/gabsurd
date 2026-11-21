//// Event operations for the Absurd durable workflow system.
//// Provides functions for emitting and awaiting events.

import gabsurd/client.{type Db, type GabsurdError}
import gabsurd/internal/query
import gabsurd/internal/sql
import gleam/json
import gleam/option
import gleam/result

/// Result of an await_event call.
pub type AwaitResult {
  AwaitResult(should_suspend: Bool, payload: String)
}

/// Emit an event to a queue.
pub fn emit(
  db: Db,
  queue_name: String,
  event_name: String,
  payload: json.Json,
) -> Result(Nil, GabsurdError) {
  sql.emit_event(client.connection(db), queue_name, event_name, payload)
  |> query.exec
}

/// Await an event for a specific task step.
/// Returns an AwaitResult indicating whether the task should suspend
/// (no event available) or continue (event received).
pub fn await(
  db: Db,
  queue_name: String,
  task_id: BitArray,
  run_id: BitArray,
  step_name: String,
  event_name: String,
  timeout: Int,
) -> Result(AwaitResult, GabsurdError) {
  use task_id <- result.try(query.uuid_from_bits(task_id))
  use run_id <- result.try(query.uuid_from_bits(run_id))
  use row <- result.try(
    sql.await_event(
      client.connection(db),
      queue_name,
      task_id,
      run_id,
      step_name,
      event_name,
      timeout,
    )
    |> query.one,
  )
  // Keep the legacy payload until the public API has a timeout outcome.
  Ok(AwaitResult(
    should_suspend: row.should_suspend,
    payload: option.unwrap(row.payload, "{}"),
  ))
}
