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
FROM gabsurd.await_event($1, $2, $3, $4, $5, $6);
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

/// A row you get from running the `await_event_if_claimed` query
/// defined in `./src/gabsurd/internal/sql/await_event_if_claimed.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type AwaitEventIfClaimedRow {
  AwaitEventIfClaimedRow(
    claim_lost: Bool,
    should_suspend: Bool,
    payload: Option(String),
  )
}

/// A timed event wait that checks the claim before a write.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn await_event_if_claimed(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: String,
  arg_4: String,
  arg_5: String,
  arg_6: Int,
) -> Result(pog.Returned(AwaitEventIfClaimedRow), pog.QueryError) {
  let decoder = {
    use claim_lost <- decode.field(0, decode.bool)
    use should_suspend <- decode.field(1, decode.bool)
    use payload <- decode.field(2, decode.optional(decode.string))
    decode.success(AwaitEventIfClaimedRow(
      claim_lost:,
      should_suspend:,
      payload:,
    ))
  }

  "-- A timed event wait that checks the claim before a write.
SELECT claim_lost, should_suspend, payload::text AS \"payload?\"
FROM gabsurd.await_event($1, NULL::uuid, $2, $4, $5, $6, $3);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(arg_3))
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
FROM gabsurd.await_event($1, $2, $3, $4, $5, NULL::integer);
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

/// A row you get from running the `await_event_unlimited_if_claimed` query
/// defined in `./src/gabsurd/internal/sql/await_event_unlimited_if_claimed.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type AwaitEventUnlimitedIfClaimedRow {
  AwaitEventUnlimitedIfClaimedRow(
    claim_lost: Bool,
    should_suspend: Bool,
    payload: Option(String),
  )
}

/// An event wait with no deadline that checks the claim before a write.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn await_event_unlimited_if_claimed(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: String,
  arg_4: String,
  arg_5: String,
) -> Result(pog.Returned(AwaitEventUnlimitedIfClaimedRow), pog.QueryError) {
  let decoder = {
    use claim_lost <- decode.field(0, decode.bool)
    use should_suspend <- decode.field(1, decode.bool)
    use payload <- decode.field(2, decode.optional(decode.string))
    decode.success(AwaitEventUnlimitedIfClaimedRow(
      claim_lost:,
      should_suspend:,
      payload:,
    ))
  }

  "-- An event wait with no deadline that checks the claim before a write.
SELECT claim_lost, should_suspend, payload::text AS \"payload?\"
FROM gabsurd.await_event($1, NULL::uuid, $2, $4, $5, NULL::integer, $3);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(arg_3))
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
FROM gabsurd.claim_task($1, $2, $3, $4);
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

/// A row you get from running the `complete_run_if_claimed` query
/// defined in `./src/gabsurd/internal/sql/complete_run_if_claimed.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CompleteRunIfClaimedRow {
  CompleteRunIfClaimedRow(completed: Bool)
}

/// Complete a run only while the original claim is active.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn complete_run_if_claimed(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: String,
  arg_4: Json,
) -> Result(pog.Returned(CompleteRunIfClaimedRow), pog.QueryError) {
  let decoder = {
    use completed <- decode.field(0, decode.bool)
    decode.success(CompleteRunIfClaimedRow(completed:))
  }

  "-- Complete a run only while the original claim is active.
SELECT gabsurd.complete_run_if_claimed($1, $2, $3, $4) AS completed;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(json.to_string(arg_4)))
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

/// A row you get from running the `expired_claims` query
/// defined in `./src/gabsurd/internal/sql/expired_claims.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ExpiredClaimsRow {
  ExpiredClaimsRow(run_id: Uuid, claim_owner: String)
}

/// Find the worker's expired leases without claiming any new work.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn expired_claims(
  db: pog.Connection,
  arg_1: String,
  arg_2: List(Uuid),
  arg_3: List(String),
) -> Result(pog.Returned(ExpiredClaimsRow), pog.QueryError) {
  let decoder = {
    use run_id <- decode.field(0, uuid_decoder())
    use claim_owner <- decode.field(1, decode.string)
    decode.success(ExpiredClaimsRow(run_id:, claim_owner:))
  }

  "-- Find the worker's expired leases without claiming any new work.
SELECT run_id, claim_owner
FROM gabsurd.expired_claims($1, $2, $3);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(
    pog.array(fn(value) { pog.text(uuid.to_string(value)) }, arg_2),
  )
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_3))
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

/// A row you get from running the `extend_claim_if_claimed` query
/// defined in `./src/gabsurd/internal/sql/extend_claim_if_claimed.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ExtendClaimIfClaimedRow {
  ExtendClaimIfClaimedRow(extended: Bool)
}

/// Extend a lease only while the original claim is active.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn extend_claim_if_claimed(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: String,
  arg_4: Int,
) -> Result(pog.Returned(ExtendClaimIfClaimedRow), pog.QueryError) {
  let decoder = {
    use extended <- decode.field(0, decode.bool)
    decode.success(ExtendClaimIfClaimedRow(extended:))
  }

  "-- Extend a lease only while the original claim is active.
SELECT gabsurd.extend_claim_if_claimed($1, $2, $3, $4) AS extended;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.int(arg_4))
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

/// A row you get from running the `fail_run_if_claimed` query
/// defined in `./src/gabsurd/internal/sql/fail_run_if_claimed.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type FailRunIfClaimedRow {
  FailRunIfClaimedRow(failed: Bool)
}

/// Fail a run only while it is still owned by the same claim.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn fail_run_if_claimed(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: String,
  arg_4: Json,
) -> Result(pog.Returned(FailRunIfClaimedRow), pog.QueryError) {
  let decoder = {
    use failed <- decode.field(0, decode.bool)
    decode.success(FailRunIfClaimedRow(failed:))
  }

  "-- Fail a run only while it is still owned by the same claim.
SELECT gabsurd.fail_run_if_claimed($1, $2, $3, $4) AS failed;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(json.to_string(arg_4)))
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
    headers: Option(String),
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
    use headers <- decode.field(2, decode.optional(decode.string))
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
  headers AS \"headers?\",
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

/// Schedule a run relative to the database clock.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn schedule_run(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: Int,
) -> Result(pog.Returned(ScheduleRunRow), pog.QueryError) {
  let decoder = {
    use ignored <- decode.field(0, decode.string)
    decode.success(ScheduleRunRow(ignored:))
  }

  "-- Schedule a run relative to the database clock.
SELECT absurd.schedule_run($1, $2, absurd.current_time() + make_interval(secs => $3::bigint))::text AS ignored;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `schedule_run_if_claimed` query
/// defined in `./src/gabsurd/internal/sql/schedule_run_if_claimed.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ScheduleRunIfClaimedRow {
  ScheduleRunIfClaimedRow(scheduled: Bool)
}

/// Schedule a run only while the original claim is active.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn schedule_run_if_claimed(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: String,
  arg_4: Int,
) -> Result(pog.Returned(ScheduleRunIfClaimedRow), pog.QueryError) {
  let decoder = {
    use scheduled <- decode.field(0, decode.bool)
    decode.success(ScheduleRunIfClaimedRow(scheduled:))
  }

  "-- Schedule a run only while the original claim is active.
SELECT gabsurd.schedule_run_if_claimed($1, $2, $3, $4) AS scheduled;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.int(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `set_checkpoint_if_claimed` query
/// defined in `./src/gabsurd/internal/sql/set_checkpoint_if_claimed.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SetCheckpointIfClaimedRow {
  SetCheckpointIfClaimedRow(saved: Bool)
}

/// Save a checkpoint only while the original claim is active.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn set_checkpoint_if_claimed(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: String,
  arg_4: String,
  arg_5: Json,
  arg_6: Int,
) -> Result(pog.Returned(SetCheckpointIfClaimedRow), pog.QueryError) {
  let decoder = {
    use saved <- decode.field(0, decode.bool)
    decode.success(SetCheckpointIfClaimedRow(saved:))
  }

  "-- Save a checkpoint only while the original claim is active.
SELECT gabsurd.set_checkpoint_if_claimed($1, $2, $3, $4, $5, $6) AS saved;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(json.to_string(arg_5)))
  |> pog.parameter(pog.int(arg_6))
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

  "SELECT gabsurd.set_task_checkpoint_state($1, $2, $3, $4, $5, $6)::text AS ignored;
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

/// A row you get from running the `sleep_for_if_claimed` query
/// defined in `./src/gabsurd/internal/sql/sleep_for_if_claimed.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SleepForIfClaimedRow {
  SleepForIfClaimedRow(claim_lost: Bool, should_suspend: Bool)
}

/// Calculate the deadline on the server only when the checkpoint is new.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn sleep_for_if_claimed(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: String,
  arg_4: String,
  arg_5: Float,
  arg_6: Int,
) -> Result(pog.Returned(SleepForIfClaimedRow), pog.QueryError) {
  let decoder = {
    use claim_lost <- decode.field(0, decode.bool)
    use should_suspend <- decode.field(1, decode.bool)
    decode.success(SleepForIfClaimedRow(claim_lost:, should_suspend:))
  }

  "-- Calculate the deadline on the server only when the checkpoint is new.
SELECT claim_lost, should_suspend
FROM gabsurd.sleep_if_claimed($1, $2, $3, $4, $5, NULL::timestamptz, $6);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.float(arg_5))
  |> pog.parameter(pog.int(arg_6))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `sleep_until_if_claimed` query
/// defined in `./src/gabsurd/internal/sql/sleep_until_if_claimed.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SleepUntilIfClaimedRow {
  SleepUntilIfClaimedRow(claim_lost: Bool, should_suspend: Bool)
}

/// Interpret the encoded timestamp as UTC, not as session-local time.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn sleep_until_if_claimed(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
  arg_3: String,
  arg_4: String,
  arg_5: Timestamp,
  arg_6: Int,
) -> Result(pog.Returned(SleepUntilIfClaimedRow), pog.QueryError) {
  let decoder = {
    use claim_lost <- decode.field(0, decode.bool)
    use should_suspend <- decode.field(1, decode.bool)
    decode.success(SleepUntilIfClaimedRow(claim_lost:, should_suspend:))
  }

  "-- Interpret the encoded timestamp as UTC, not as session-local time.
SELECT claim_lost, should_suspend
FROM gabsurd.sleep_if_claimed($1, $2, $3, $4, NULL::double precision, $5::timestamp AT TIME ZONE 'UTC', $6);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.timestamp(arg_5))
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
