//// Checkpoint operations for the Absurd durable workflow system.
//// Provides functions for setting and getting task checkpoint state.
////
//// Checkpoints serve a dual purpose in Absurd:
////   1. They persist step results so completed steps are skipped on retry.
////   2. They extend the worker's claim lease by `extend_claim_by` seconds.
////
//// The second behaviour is the primary lease extension mechanism — every
//// checkpoint write keeps the worker's claim alive, so tasks with many
//// short steps never time out.  For handlers that do a single long-running
//// operation without checkpoints, see `gabsurd/task.extend_claim`.

import gabsurd/client.{type Db, type GabsurdError, NotFound}
import gabsurd/internal/query
import gabsurd/internal/sql
import gleam/json
import gleam/option
import gleam/result
import gleam/time/timestamp.{type Timestamp}
import youid/uuid

/// A checkpoint record.
pub type Checkpoint {
  Checkpoint(
    checkpoint_name: String,
    state: String,
    status: String,
    owner_run_id: BitArray,
    updated_at: Timestamp,
  )
}

/// Set a checkpoint for a task step.
///
/// `extend_claim_by` is the number of seconds to extend the worker's claim
/// lease. Pass your worker's `claim_timeout` value here so that every
/// checkpoint write keeps the lease alive. Pass `0` to skip extension.
pub fn set(
  db: Db,
  queue_name: String,
  task_id: BitArray,
  step_name: String,
  state: json.Json,
  owner_run_id: BitArray,
  extend_claim_by: Int,
) -> Result(Nil, GabsurdError) {
  use task_id <- result.try(query.uuid_from_bits(task_id))
  use owner_run_id <- result.try(query.uuid_from_bits(owner_run_id))
  sql.set_task_checkpoint_state(
    client.connection(db),
    queue_name,
    task_id,
    step_name,
    state,
    owner_run_id,
    extend_claim_by,
  )
  |> query.exec
}

/// Get a checkpoint for a task step.
/// Returns `Ok(Some(checkpoint))` if found, `Ok(None)` if not found,
/// or `Error(GabsurdError)` on database failure.
pub fn get(
  db: Db,
  queue_name: String,
  task_id: BitArray,
  step_name: String,
  include_pending: Bool,
) -> Result(option.Option(Checkpoint), GabsurdError) {
  use task_id <- result.try(query.uuid_from_bits(task_id))
  case
    sql.get_task_checkpoint_state(
      client.connection(db),
      queue_name,
      task_id,
      step_name,
      include_pending,
    )
    |> query.one
  {
    Ok(row) ->
      Ok(
        option.Some(Checkpoint(
          checkpoint_name: row.checkpoint_name,
          state: option.unwrap(row.state, "{}"),
          status: row.status,
          owner_run_id: row.owner_run_id
            |> option.map(uuid.to_bit_array)
            |> option.unwrap(<<0:128>>),
          updated_at: row.updated_at,
        )),
      )
    Error(NotFound) -> Ok(option.None)
    Error(e) -> Error(e)
  }
}
