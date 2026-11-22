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
import gabsurd/task.{type RunId, type TaskId, RunId, TaskId}
import gleam/json
import gleam/option
import gleam/time/timestamp.{type Timestamp}

/// A checkpoint record. SQL NULL state or owner is `None`.
pub type Checkpoint {
  Checkpoint(
    checkpoint_name: String,
    state: option.Option(String),
    status: String,
    owner_run_id: option.Option(RunId),
    updated_at: Timestamp,
  )
}

/// Set a checkpoint for a task step. The run must belong to the given task.
///
/// This function does not check the claim owner or expiry. In a worker
/// handler, use `context.set_checkpoint` instead.
///
/// `extend_claim_by` is the number of seconds to extend the worker's claim
/// lease. Pass `0` to save the checkpoint without renewing the lease.
pub fn set(
  db db: Db,
  queue_name queue_name: String,
  task_id task_id: TaskId,
  step_name step_name: String,
  state state: json.Json,
  owner_run_id owner_run_id: RunId,
  extend_claim_by extend_claim_by: Int,
) -> Result(Nil, GabsurdError) {
  let TaskId(task_uuid) = task_id
  let RunId(owner_uuid) = owner_run_id
  sql.set_task_checkpoint_state(
    client.connection(db),
    queue_name,
    task_uuid,
    step_name,
    state,
    owner_uuid,
    extend_claim_by,
  )
  |> query.exec
}

/// Get a checkpoint for a task step.
/// Returns `Ok(Some(checkpoint))` if found, `Ok(None)` if not found,
/// or `Error(GabsurdError)` on database failure.
pub fn get(
  db db: Db,
  queue_name queue_name: String,
  task_id task_id: TaskId,
  step_name step_name: String,
  include_pending include_pending: Bool,
) -> Result(option.Option(Checkpoint), GabsurdError) {
  let TaskId(task_uuid) = task_id
  case
    sql.get_task_checkpoint_state(
      client.connection(db),
      queue_name,
      task_uuid,
      step_name,
      include_pending,
    )
    |> query.one
  {
    Ok(row) ->
      Ok(
        option.Some(Checkpoint(
          checkpoint_name: row.checkpoint_name,
          state: row.state,
          status: row.status,
          owner_run_id: option.map(row.owner_run_id, RunId),
          updated_at: row.updated_at,
        )),
      )
    Error(NotFound) -> Ok(option.None)
    Error(e) -> Error(e)
  }
}
