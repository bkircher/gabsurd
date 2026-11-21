//// This module contains the code to run the sql queries defined in
//// `./src/gabsurd/internal/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{type Option}
import gleam/time/timestamp.{type Timestamp}
import pog
import youid/uuid.{type Uuid}

/// A row you get from running the `await_event` query
/// defined in `./src/gabsurd/internal/sql/await_event.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type AwaitEventRow {
  AwaitEventRow(should_suspend: Bool, payload: Option(String))
}

/// A timed wait. Keep SQL NULL distinct from the JSON value null.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn await_event(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: Uuid,
  arg_4: String,
  arg_5: String,
  arg_6: Int,
) -> Result(pog.Returned(AwaitEventRow), pog.QueryError) {
  let decoder = {
    use should_suspend <- decode.field(0, decode.bool)
    use payload <- decode.field(1, decode.optional(decode.string))
    decode.success(AwaitEventRow(should_suspend:, payload:))
  }

  "-- A timed wait. Keep SQL NULL distinct from the JSON value null.
SELECT should_suspend, payload::text AS \"payload?\"
FROM absurd.await_event($1, $2, $3, $4, $5, $6);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(uuid.to_string(arg_3)))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.parameter(pog.int(arg_6))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `await_event_unlimited` query
/// defined in `./src/gabsurd/internal/sql/await_event_unlimited.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type AwaitEventUnlimitedRow {
  AwaitEventUnlimitedRow(should_suspend: Bool, payload: Option(String))
}

/// An event wait with no deadline.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn await_event_unlimited(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: Uuid,
  arg_4: String,
  arg_5: String,
) -> Result(pog.Returned(AwaitEventUnlimitedRow), pog.QueryError) {
  let decoder = {
    use should_suspend <- decode.field(0, decode.bool)
    use payload <- decode.field(1, decode.optional(decode.string))
    decode.success(AwaitEventUnlimitedRow(should_suspend:, payload:))
  }

  "-- An event wait with no deadline.
SELECT should_suspend, payload::text AS \"payload?\"
FROM absurd.await_event($1, $2, $3, $4, $5, NULL::integer);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(uuid.to_string(arg_3)))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `cancel_task` query
/// defined in `./src/gabsurd/internal/sql/cancel_task.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CancelTaskRow {
  CancelTaskRow(ignored: String)
}

/// Runs the `cancel_task` query
/// defined in `./src/gabsurd/internal/sql/cancel_task.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn cancel_task(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
) -> Result(pog.Returned(CancelTaskRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(CancelTaskRow(ignored:))
  }

  "SELECT absurd.cancel_task($1, $2)::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `claim_task` query
/// defined in `./src/gabsurd/internal/sql/claim_task.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ClaimTaskRow {
  ClaimTaskRow(
    run_id: Uuid,
    task_id: Uuid,
    attempt: Int,
    task_name: String,
    params: String,
    retry_strategy: Option(String),
    max_attempts: Option(Int),
    headers: Option(String),
    wake_event: Option(String),
    event_payload: Option(String),
  )
}

/// Claim up to the requested number of ready runs.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn claim_task(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: Int,
  arg_4: Int,
) -> Result(pog.Returned(ClaimTaskRow), pog.QueryError) {
  let decoder = {
    use run_id <- decode.field(0, uuid_decoder())
    use task_id <- decode.field(1, uuid_decoder())
    use attempt <- decode.field(2, decode.int)
    use task_name <- decode.field(3, decode.string)
    use params <- decode.field(4, decode.string)
    use retry_strategy <- decode.field(5, decode.optional(decode.string))
    use max_attempts <- decode.field(6, decode.optional(decode.int))
    use headers <- decode.field(7, decode.optional(decode.string))
    use wake_event <- decode.field(8, decode.optional(decode.string))
    use event_payload <- decode.field(9, decode.optional(decode.string))
    decode.success(ClaimTaskRow(
      run_id:,
      task_id:,
      attempt:,
      task_name:,
      params:,
      retry_strategy:,
      max_attempts:,
      headers:,
      wake_event:,
      event_payload:,
    ))
  }

  "-- Claim up to the requested number of ready runs.
SELECT
  run_id,
  task_id,
  attempt,
  task_name,
  params,
  retry_strategy AS \"retry_strategy?\",
  max_attempts AS \"max_attempts?\",
  headers AS \"headers?\",
  wake_event AS \"wake_event?\",
  event_payload AS \"event_payload?\"
FROM absurd.claim_task($1, $2, $3, $4);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.int(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `cleanup_all_queues` query
/// defined in `./src/gabsurd/internal/sql/cleanup_all_queues.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CleanupAllQueuesRow {
  CleanupAllQueuesRow(
    queue_name: String,
    tasks_deleted: Int,
    events_deleted: Int,
  )
}

/// Runs the `cleanup_all_queues` query
/// defined in `./src/gabsurd/internal/sql/cleanup_all_queues.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn cleanup_all_queues(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(CleanupAllQueuesRow), pog.QueryError) {
  let decoder = {
    use queue_name <- decode.field(0, decode.string)
    use tasks_deleted <- decode.field(1, decode.int)
    use events_deleted <- decode.field(2, decode.int)
    decode.success(CleanupAllQueuesRow(
      queue_name:,
      tasks_deleted:,
      events_deleted:,
    ))
  }

  "SELECT queue_name, tasks_deleted, events_deleted
FROM absurd.cleanup_all_queues($1);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `cleanup_events` query
/// defined in `./src/gabsurd/internal/sql/cleanup_events.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CleanupEventsRow {
  CleanupEventsRow(cleanup_events: Int)
}

/// Runs the `cleanup_events` query
/// defined in `./src/gabsurd/internal/sql/cleanup_events.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn cleanup_events(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
  arg_3: Int,
) -> Result(pog.Returned(CleanupEventsRow), pog.QueryError) {
  let decoder = {
    use cleanup_events <- decode.field(0, decode.int)
    decode.success(CleanupEventsRow(cleanup_events:))
  }

  "SELECT absurd.cleanup_events($1, $2, $3) AS cleanup_events;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `cleanup_tasks` query
/// defined in `./src/gabsurd/internal/sql/cleanup_tasks.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CleanupTasksRow {
  CleanupTasksRow(cleanup_tasks: Int)
}

/// Runs the `cleanup_tasks` query
/// defined in `./src/gabsurd/internal/sql/cleanup_tasks.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn cleanup_tasks(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
  arg_3: Int,
) -> Result(pog.Returned(CleanupTasksRow), pog.QueryError) {
  let decoder = {
    use cleanup_tasks <- decode.field(0, decode.int)
    decode.success(CleanupTasksRow(cleanup_tasks:))
  }

  "SELECT absurd.cleanup_tasks($1, $2, $3) AS cleanup_tasks;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `complete_run` query
/// defined in `./src/gabsurd/internal/sql/complete_run.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CompleteRunRow {
  CompleteRunRow(ignored: String)
}

/// Runs the `complete_run` query
/// defined in `./src/gabsurd/internal/sql/complete_run.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn complete_run(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: Json,
) -> Result(pog.Returned(CompleteRunRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(CompleteRunRow(ignored:))
  }

  "SELECT absurd.complete_run($1, $2, $3)::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(json.to_string(arg_3)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `create_queue` query
/// defined in `./src/gabsurd/internal/sql/create_queue.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CreateQueueRow {
  CreateQueueRow(ignored: String)
}

/// Runs the `create_queue` query
/// defined in `./src/gabsurd/internal/sql/create_queue.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn create_queue(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(CreateQueueRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(CreateQueueRow(ignored:))
  }

  "SELECT absurd.create_queue($1)::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `create_queue_with_mode` query
/// defined in `./src/gabsurd/internal/sql/create_queue_with_mode.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CreateQueueWithModeRow {
  CreateQueueWithModeRow(ignored: String)
}

/// Runs the `create_queue_with_mode` query
/// defined in `./src/gabsurd/internal/sql/create_queue_with_mode.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn create_queue_with_mode(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
) -> Result(pog.Returned(CreateQueueWithModeRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(CreateQueueWithModeRow(ignored:))
  }

  "SELECT absurd.create_queue($1, $2)::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `drop_queue` query
/// defined in `./src/gabsurd/internal/sql/drop_queue.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type DropQueueRow {
  DropQueueRow(ignored: String)
}

/// Runs the `drop_queue` query
/// defined in `./src/gabsurd/internal/sql/drop_queue.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn drop_queue(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(DropQueueRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(DropQueueRow(ignored:))
  }

  "SELECT absurd.drop_queue($1)::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `emit_event` query
/// defined in `./src/gabsurd/internal/sql/emit_event.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type EmitEventRow {
  EmitEventRow(ignored: String)
}

/// Runs the `emit_event` query
/// defined in `./src/gabsurd/internal/sql/emit_event.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn emit_event(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: Json,
) -> Result(pog.Returned(EmitEventRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(EmitEventRow(ignored:))
  }

  "SELECT absurd.emit_event($1, $2, $3)::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(json.to_string(arg_3)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `extend_claim` query
/// defined in `./src/gabsurd/internal/sql/extend_claim.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ExtendClaimRow {
  ExtendClaimRow(ignored: String)
}

/// Runs the `extend_claim` query
/// defined in `./src/gabsurd/internal/sql/extend_claim.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn extend_claim(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: Int,
) -> Result(pog.Returned(ExtendClaimRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(ExtendClaimRow(ignored:))
  }

  "SELECT absurd.extend_claim($1, $2, $3)::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `fail_run` query
/// defined in `./src/gabsurd/internal/sql/fail_run.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type FailRunRow {
  FailRunRow(ignored: String)
}

/// Runs the `fail_run` query
/// defined in `./src/gabsurd/internal/sql/fail_run.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn fail_run(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: Json,
) -> Result(pog.Returned(FailRunRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(FailRunRow(ignored:))
  }

  "SELECT absurd.fail_run($1, $2, $3, NULL::timestamptz)::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(json.to_string(arg_3)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `fail_run_with_retry` query
/// defined in `./src/gabsurd/internal/sql/fail_run_with_retry.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type FailRunWithRetryRow {
  FailRunWithRetryRow(ignored: String)
}

/// Interpret the encoded timestamp as UTC, not as session-local time.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn fail_run_with_retry(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: Json,
  arg_4: Timestamp,
) -> Result(pog.Returned(FailRunWithRetryRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(FailRunWithRetryRow(ignored:))
  }

  "-- Interpret the encoded timestamp as UTC, not as session-local time.
SELECT absurd.fail_run($1, $2, $3, $4::timestamp AT TIME ZONE 'UTC')::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(json.to_string(arg_3)))
  |> pog.parameter(pog.timestamp(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_queue_policy` query
/// defined in `./src/gabsurd/internal/sql/get_queue_policy.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetQueuePolicyRow {
  GetQueuePolicyRow(
    queue_name: String,
    storage_mode: String,
    default_partition: String,
    partition_lookahead: String,
    partition_lookback: String,
    cleanup_ttl: String,
    cleanup_limit: Int,
    detach_mode: String,
    detach_min_age: String,
  )
}

/// Runs the `get_queue_policy` query
/// defined in `./src/gabsurd/internal/sql/get_queue_policy.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_queue_policy(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(GetQueuePolicyRow), pog.QueryError) {
  let decoder = {
    use queue_name <- decode.field(0, decode.string)
    use storage_mode <- decode.field(1, decode.string)
    use default_partition <- decode.field(2, decode.string)
    use partition_lookahead <- decode.field(3, decode.string)
    use partition_lookback <- decode.field(4, decode.string)
    use cleanup_ttl <- decode.field(5, decode.string)
    use cleanup_limit <- decode.field(6, decode.int)
    use detach_mode <- decode.field(7, decode.string)
    use detach_min_age <- decode.field(8, decode.string)
    decode.success(GetQueuePolicyRow(
      queue_name:,
      storage_mode:,
      default_partition:,
      partition_lookahead:,
      partition_lookback:,
      cleanup_ttl:,
      cleanup_limit:,
      detach_mode:,
      detach_min_age:,
    ))
  }

  "SELECT
  queue_name,
  storage_mode,
  default_partition,
  partition_lookahead::text,
  partition_lookback::text,
  cleanup_ttl::text,
  cleanup_limit,
  detach_mode,
  detach_min_age::text
FROM absurd.get_queue_policy($1);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_schema_version` query
/// defined in `./src/gabsurd/internal/sql/get_schema_version.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetSchemaVersionRow {
  GetSchemaVersionRow(get_schema_version: String)
}

/// Runs the `get_schema_version` query
/// defined in `./src/gabsurd/internal/sql/get_schema_version.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_schema_version(
  db: pog.Connection,
) -> Result(pog.Returned(GetSchemaVersionRow), pog.QueryError) {
  let decoder = {
    use get_schema_version <- decode.field(0, decode.string)
    decode.success(GetSchemaVersionRow(get_schema_version:))
  }

  "SELECT absurd.get_schema_version() AS get_schema_version;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_task_checkpoint_state` query
/// defined in `./src/gabsurd/internal/sql/get_task_checkpoint_state.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetTaskCheckpointStateRow {
  GetTaskCheckpointStateRow(
    checkpoint_name: String,
    state: Option(String),
    status: String,
    owner_run_id: Option(Uuid),
    updated_at: Timestamp,
  )
}

/// Runs the `get_task_checkpoint_state` query
/// defined in `./src/gabsurd/internal/sql/get_task_checkpoint_state.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_task_checkpoint_state(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: String,
  arg_4: Bool,
) -> Result(pog.Returned(GetTaskCheckpointStateRow), pog.QueryError) {
  let decoder = {
    use checkpoint_name <- decode.field(0, decode.string)
    use state <- decode.field(1, decode.optional(decode.string))
    use status <- decode.field(2, decode.string)
    use owner_run_id <- decode.field(3, decode.optional(uuid_decoder()))
    use updated_at <- decode.field(4, pog.timestamp_decoder())
    decode.success(GetTaskCheckpointStateRow(
      checkpoint_name:,
      state:,
      status:,
      owner_run_id:,
      updated_at:,
    ))
  }

  "SELECT
  checkpoint_name,
  state AS \"state?\",
  status,
  owner_run_id AS \"owner_run_id?\",
  updated_at AT TIME ZONE 'UTC' AS updated_at
FROM absurd.get_task_checkpoint_state($1, $2, $3, $4);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.bool(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_task_checkpoint_states` query
/// defined in `./src/gabsurd/internal/sql/get_task_checkpoint_states.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetTaskCheckpointStatesRow {
  GetTaskCheckpointStatesRow(
    checkpoint_name: String,
    state: Option(String),
    status: String,
    owner_run_id: Option(Uuid),
    updated_at: Timestamp,
  )
}

/// Runs the `get_task_checkpoint_states` query
/// defined in `./src/gabsurd/internal/sql/get_task_checkpoint_states.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_task_checkpoint_states(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: Uuid,
) -> Result(pog.Returned(GetTaskCheckpointStatesRow), pog.QueryError) {
  let decoder = {
    use checkpoint_name <- decode.field(0, decode.string)
    use state <- decode.field(1, decode.optional(decode.string))
    use status <- decode.field(2, decode.string)
    use owner_run_id <- decode.field(3, decode.optional(uuid_decoder()))
    use updated_at <- decode.field(4, pog.timestamp_decoder())
    decode.success(GetTaskCheckpointStatesRow(
      checkpoint_name:,
      state:,
      status:,
      owner_run_id:,
      updated_at:,
    ))
  }

  "SELECT
  checkpoint_name,
  state AS \"state?\",
  status,
  owner_run_id AS \"owner_run_id?\",
  updated_at AT TIME ZONE 'UTC' AS updated_at
FROM absurd.get_task_checkpoint_states($1, $2, $3);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(uuid.to_string(arg_3)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_task_result` query
/// defined in `./src/gabsurd/internal/sql/get_task_result.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetTaskResultRow {
  GetTaskResultRow(
    task_id: Uuid,
    task_name: String,
    headers: String,
    state: String,
    result: Option(String),
    failure_reason: Option(String),
  )
}

/// Runs the `get_task_result` query
/// defined in `./src/gabsurd/internal/sql/get_task_result.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_task_result(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
) -> Result(pog.Returned(GetTaskResultRow), pog.QueryError) {
  let decoder = {
    use task_id <- decode.field(0, uuid_decoder())
    use task_name <- decode.field(1, decode.string)
    use headers <- decode.field(2, decode.string)
    use state <- decode.field(3, decode.string)
    use result <- decode.field(4, decode.optional(decode.string))
    use failure_reason <- decode.field(5, decode.optional(decode.string))
    decode.success(GetTaskResultRow(
      task_id:,
      task_name:,
      headers:,
      state:,
      result:,
      failure_reason:,
    ))
  }

  "SELECT
  task_id,
  task_name,
  headers,
  state,
  result AS \"result?\",
  failure_reason AS \"failure_reason?\"
FROM gabsurd.get_task_result($1, $2);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `list_queues` query
/// defined in `./src/gabsurd/internal/sql/list_queues.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ListQueuesRow {
  ListQueuesRow(queue_name: String)
}

/// Runs the `list_queues` query
/// defined in `./src/gabsurd/internal/sql/list_queues.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn list_queues(
  db: pog.Connection,
) -> Result(pog.Returned(ListQueuesRow), pog.QueryError) {
  let decoder = {
    use queue_name <- decode.field(0, decode.string)
    decode.success(ListQueuesRow(queue_name:))
  }

  "SELECT queue_name
FROM absurd.list_queues();
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `retry_task` query
/// defined in `./src/gabsurd/internal/sql/retry_task.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type RetryTaskRow {
  RetryTaskRow(task_id: Uuid, run_id: Uuid, attempt: Int, created: Bool)
}

/// Runs the `retry_task` query
/// defined in `./src/gabsurd/internal/sql/retry_task.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn retry_task(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: Json,
) -> Result(pog.Returned(RetryTaskRow), pog.QueryError) {
  let decoder = {
    use task_id <- decode.field(0, uuid_decoder())
    use run_id <- decode.field(1, uuid_decoder())
    use attempt <- decode.field(2, decode.int)
    use created <- decode.field(3, decode.bool)
    decode.success(RetryTaskRow(task_id:, run_id:, attempt:, created:))
  }

  "SELECT task_id, run_id, attempt, created
FROM absurd.retry_task($1, $2, $3);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(json.to_string(arg_3)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `schedule_run` query
/// defined in `./src/gabsurd/internal/sql/schedule_run.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ScheduleRunRow {
  ScheduleRunRow(ignored: String)
}

/// Interpret the encoded timestamp as UTC, not as session-local time.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn schedule_run(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: Timestamp,
) -> Result(pog.Returned(ScheduleRunRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(ScheduleRunRow(ignored:))
  }

  "-- Interpret the encoded timestamp as UTC, not as session-local time.
SELECT absurd.schedule_run($1, $2, $3::timestamp AT TIME ZONE 'UTC')::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.timestamp(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `set_queue_policy` query
/// defined in `./src/gabsurd/internal/sql/set_queue_policy.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SetQueuePolicyRow {
  SetQueuePolicyRow(ignored: String)
}

/// Runs the `set_queue_policy` query
/// defined in `./src/gabsurd/internal/sql/set_queue_policy.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn set_queue_policy(
  db: pog.Connection,
  arg_1: String,
  arg_2: Json,
) -> Result(pog.Returned(SetQueuePolicyRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(SetQueuePolicyRow(ignored:))
  }

  "SELECT absurd.set_queue_policy($1, $2)::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(json.to_string(arg_2)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `set_task_checkpoint_state` query
/// defined in `./src/gabsurd/internal/sql/set_task_checkpoint_state.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SetTaskCheckpointStateRow {
  SetTaskCheckpointStateRow(ignored: String)
}

/// Runs the `set_task_checkpoint_state` query
/// defined in `./src/gabsurd/internal/sql/set_task_checkpoint_state.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn set_task_checkpoint_state(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: String,
  arg_4: Json,
  arg_5: Uuid,
  arg_6: Int,
) -> Result(pog.Returned(SetTaskCheckpointStateRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(SetTaskCheckpointStateRow(ignored:))
  }

  "SELECT absurd.set_task_checkpoint_state($1, $2, $3, $4, $5, $6)::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(json.to_string(arg_4)))
  |> pog.parameter(pog.text(uuid.to_string(arg_5)))
  |> pog.parameter(pog.int(arg_6))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `spawn_task` query
/// defined in `./src/gabsurd/internal/sql/spawn_task.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SpawnTaskRow {
  SpawnTaskRow(task_id: Uuid, run_id: Uuid, attempt: Int, created: Bool)
}

/// Runs the `spawn_task` query
/// defined in `./src/gabsurd/internal/sql/spawn_task.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn spawn_task(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: Json,
  arg_4: Json,
) -> Result(pog.Returned(SpawnTaskRow), pog.QueryError) {
  let decoder = {
    use task_id <- decode.field(0, uuid_decoder())
    use run_id <- decode.field(1, uuid_decoder())
    use attempt <- decode.field(2, decode.int)
    use created <- decode.field(3, decode.bool)
    decode.success(SpawnTaskRow(task_id:, run_id:, attempt:, created:))
  }

  "SELECT task_id, run_id, attempt, created
FROM absurd.spawn_task($1, $2, $3, $4);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(json.to_string(arg_3)))
  |> pog.parameter(pog.text(json.to_string(arg_4)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

// --- Encoding/decoding utils -------------------------------------------------

/// A decoder to decode `Uuid`s coming from a Postgres query.
///
fn uuid_decoder() {
  use bit_array <- decode.then(decode.bit_array)
  case uuid.from_bit_array(bit_array) {
    Ok(uuid) -> decode.success(uuid)
    Error(_) -> decode.failure(uuid.v7(), "Uuid")
  }
}
