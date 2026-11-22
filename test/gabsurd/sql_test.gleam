//// Integration tests for generated SQL and database type conversions.

import gabsurd/client
import gabsurd/internal/sql
import gabsurd/test_support
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/time/timestamp
import gleeunit/should
import pog
import youid/uuid

const start_time = "2025-01-02T03:04:05.123456Z"

const due_time = "2025-01-02T03:05:05.123456Z"

fn with_queue(name: String, check: fn(pog.Connection, String) -> Nil) -> Nil {
  use db, queue <- test_support.with_transaction_queue(name)
  test_support.set_time(db:, at: start_time)
  check(client.connection(db), queue)
}

fn set_local(
  db db: pog.Connection,
  setting setting: String,
  value value: String,
) -> Nil {
  let assert Ok(_) =
    pog.query("SELECT set_config($1, $2, true)")
    |> pog.parameter(pog.text(setting))
    |> pog.parameter(pog.text(value))
    |> pog.execute(db)
  Nil
}

fn claimed_task(db: pog.Connection, queue: String) -> sql.ClaimTaskRow {
  let assert Ok(pog.Returned(1, [spawned])) =
    sql.spawn_task(db, queue, "task", json.null(), json.object([]))
  let assert Ok(pog.Returned(1, [claim])) =
    sql.claim_task(db, queue, "worker", 30, 1)
  claim.task_id |> should.equal(spawned.task_id)
  claim.run_id |> should.equal(spawned.run_id)
  claim
}

pub fn claim_preserves_optional_values_test() -> Nil {
  use db, queue <- with_queue("squirrel_claim")
  sql.claim_task(db, queue, "worker", 30, 2)
  |> should.equal(Ok(pog.Returned(0, [])))
  let assert Ok(pog.Returned(1, [bare])) =
    sql.spawn_task(db, queue, "bare", json.null(), json.object([]))
  let assert Ok(pog.Returned(1, [configured])) =
    sql.spawn_task(
      db,
      queue,
      "configured",
      json.object([#("value", json.int(42))]),
      json.object([
        #("max_attempts", json.int(3)),
        #("headers", json.null()),
        #("retry_strategy", json.object([#("kind", json.string("fixed"))])),
      ]),
    )

  let assert Ok(pog.Returned(2, rows)) =
    sql.claim_task(db, queue, "worker", 30, 2)

  let assert [first, second] =
    list.sort(rows, fn(a, b) { string.compare(a.task_name, b.task_name) })
  first.task_id |> should.equal(bare.task_id)
  first.run_id |> should.equal(bare.run_id)
  first.params |> should.equal("null")
  first.max_attempts |> should.equal(None)
  first.headers |> should.equal(None)
  first.retry_strategy |> should.equal(None)
  first.wake_event |> should.equal(None)
  first.event_payload |> should.equal(None)
  second.task_id |> should.equal(configured.task_id)
  second.run_id |> should.equal(configured.run_id)
  second.params |> should.equal("{\"value\": 42}")
  second.max_attempts |> should.equal(Some(3))
  second.headers |> should.equal(Some("null"))
  second.retry_strategy |> should.equal(Some("{\"kind\": \"fixed\"}"))
}

pub fn timed_wait_preserves_sql_null_on_timeout_test() -> Nil {
  use db, queue <- with_queue("squirrel_timed_wait")
  let claim = claimed_task(db, queue)

  sql.await_event(db, queue, claim.task_id, claim.run_id, "step", "event", 0)
  |> should.equal(Ok(pog.Returned(1, [sql.AwaitEventRow(True, None)])))
  let assert Ok(pog.Returned(1, [resumed])) =
    sql.claim_task(db, queue, "worker", 30, 1)
  resumed.run_id |> should.equal(claim.run_id)
  resumed.wake_event |> should.equal(Some("event"))
  resumed.event_payload |> should.equal(None)

  sql.await_event(
    db,
    queue,
    resumed.task_id,
    resumed.run_id,
    "step",
    "event",
    0,
  )
  |> should.equal(Ok(pog.Returned(1, [sql.AwaitEventRow(False, None)])))
}

pub fn unlimited_wait_resumes_on_json_null_event_test() -> Nil {
  use db, queue <- with_queue("squirrel_unlimited_wait")
  let claim = claimed_task(db, queue)

  sql.await_event_unlimited(
    db,
    queue,
    claim.task_id,
    claim.run_id,
    "step",
    "event",
  )
  |> should.equal(Ok(pog.Returned(1, [sql.AwaitEventUnlimitedRow(True, None)])))
  sql.claim_task(db, queue, "worker", 30, 1)
  |> should.equal(Ok(pog.Returned(0, [])))

  let assert Ok(_) = sql.emit_event(db, queue, "event", json.null())
  let assert Ok(pog.Returned(1, [resumed])) =
    sql.claim_task(db, queue, "worker", 30, 1)
  resumed.run_id |> should.equal(claim.run_id)
  resumed.wake_event |> should.equal(None)
  resumed.event_payload |> should.equal(Some("null"))

  sql.await_event_unlimited(
    db,
    queue,
    resumed.task_id,
    resumed.run_id,
    "step",
    "event",
  )
  |> should.equal(
    Ok(pog.Returned(1, [sql.AwaitEventUnlimitedRow(False, Some("null"))])),
  )
}

pub fn await_decodes_json_object_test() -> Nil {
  use db, queue <- with_queue("squirrel_object_event")
  let claim = claimed_task(db, queue)
  let assert Ok(_) =
    sql.emit_event(db, queue, "event", json.object([#("value", json.int(42))]))

  let outcome =
    sql.await_event(db, queue, claim.task_id, claim.run_id, "step", "event", 0)

  outcome
  |> should.equal(
    Ok(pog.Returned(1, [sql.AwaitEventRow(False, Some("{\"value\": 42}"))])),
  )
}

pub fn checkpoint_reads_preserve_null_values_test() -> Nil {
  use db, queue <- with_queue("squirrel_checkpoint_null")
  let claim = claimed_task(db, queue)
  sql.get_task_checkpoint_state(db, queue, claim.task_id, "missing", False)
  |> should.equal(Ok(pog.Returned(0, [])))
  let assert Ok(_) =
    sql.set_task_checkpoint_state(
      db,
      queue,
      claim.task_id,
      "json_null",
      json.null(),
      claim.run_id,
      0,
    )
  let assert Ok(_) =
    pog.query(
      "SELECT absurd.set_task_checkpoint_state($1, $2, 'sql_null', NULL::jsonb, $3, 0)::text",
    )
    |> pog.parameter(pog.text(queue))
    |> pog.parameter(pog.text(uuid.to_string(claim.task_id)))
    |> pog.parameter(pog.text(uuid.to_string(claim.run_id)))
    |> pog.execute(db)

  let assert Ok(pog.Returned(1, [json_row])) =
    sql.get_task_checkpoint_state(db, queue, claim.task_id, "json_null", False)
  let assert Ok(pog.Returned(1, [sql_row])) =
    sql.get_task_checkpoint_state(db, queue, claim.task_id, "sql_null", False)

  json_row.state |> should.equal(Some("null"))
  sql_row.state |> should.equal(None)
}

pub fn checkpoint_timestamp_is_independent_of_session_zone_test() -> Nil {
  use db, queue <- with_queue("squirrel_checkpoint_zone")
  let claim = claimed_task(db, queue)
  let assert Ok(expected) = timestamp.parse_rfc3339(start_time)
  set_local(db:, setting: "TimeZone", value: "UTC")
  let assert Ok(_) =
    sql.set_task_checkpoint_state(
      db,
      queue,
      claim.task_id,
      "step",
      json.int(42),
      claim.run_id,
      0,
    )

  let assert Ok(pog.Returned(1, [utc])) =
    sql.get_task_checkpoint_state(db, queue, claim.task_id, "step", False)
  set_local(db:, setting: "TimeZone", value: "America/Los_Angeles")
  let assert Ok(pog.Returned(1, [local])) =
    sql.get_task_checkpoint_state(db, queue, claim.task_id, "step", False)

  local |> should.equal(utc)
  local.updated_at |> should.equal(expected)
  local.owner_run_id |> should.equal(Some(claim.run_id))
}

pub fn guarded_deferral_uses_database_time_in_a_non_utc_zone_test() -> Nil {
  use db, queue <- with_queue("squirrel_schedule_zone")
  let claim = claimed_task(db, queue)
  set_local(db:, setting: "TimeZone", value: "America/Los_Angeles")

  let write = sql.schedule_run_if_claimed(db, queue, claim.run_id, "worker", 60)

  write
  |> should.equal(Ok(pog.Returned(1, [sql.ScheduleRunIfClaimedRow(True)])))
  set_local(
    db:,
    setting: "absurd.fake_now",
    value: "2025-01-02T03:05:05.123455Z",
  )
  sql.claim_task(db, queue, "worker", 30, 1)
  |> should.equal(Ok(pog.Returned(0, [])))
  set_local(db:, setting: "absurd.fake_now", value: due_time)
  let assert Ok(pog.Returned(1, [resumed])) =
    sql.claim_task(db, queue, "worker", 30, 1)
  resumed.run_id |> should.equal(claim.run_id)
}

pub fn expired_claim_cannot_defer_a_run_test() -> Nil {
  use db, queue <- with_queue("squirrel_schedule_expired")
  let claim = claimed_task(db, queue)
  set_local(
    db:,
    setting: "absurd.fake_now",
    value: "2025-01-02T03:04:35.123456Z",
  )

  let write = sql.schedule_run_if_claimed(db, queue, claim.run_id, "worker", 60)

  write
  |> should.equal(Ok(pog.Returned(1, [sql.ScheduleRunIfClaimedRow(False)])))
  let assert Ok(pog.Returned(1, [outcome])) =
    sql.get_task_result(db, queue, claim.task_id)
  outcome.state |> should.equal("running")
}

pub fn previous_claim_cannot_defer_a_run_with_a_new_owner_test() -> Nil {
  use db, queue <- with_queue("squirrel_schedule_old")
  let old = claimed_task(db, queue)
  let assert Ok(_) = sql.schedule_run(db, queue, old.run_id, 0)
  let assert Ok(pog.Returned(1, [resumed])) =
    sql.claim_task(db, queue, "worker-2", 30, 1)

  let write = sql.schedule_run_if_claimed(db, queue, old.run_id, "worker", 60)

  resumed.run_id |> should.equal(old.run_id)
  write
  |> should.equal(Ok(pog.Returned(1, [sql.ScheduleRunIfClaimedRow(False)])))
  let assert Ok(pog.Returned(1, [outcome])) =
    sql.get_task_result(db, queue, old.task_id)
  outcome.state |> should.equal("running")
}

pub fn expired_claim_cannot_record_a_handler_failure_test() -> Nil {
  use db, queue <- with_queue("squirrel_expired_claim")
  let claim = claimed_task(db, queue)
  set_local(db:, setting: "absurd.fake_now", value: due_time)

  let write =
    sql.fail_run_if_claimed(
      db,
      queue,
      claim.run_id,
      "worker",
      json.string("Handler crash"),
    )

  write |> should.equal(Ok(pog.Returned(1, [sql.FailRunIfClaimedRow(False)])))
  let assert Ok(pog.Returned(1, [outcome])) =
    sql.get_task_result(db, queue, claim.task_id)
  outcome.state |> should.equal("running")
}

pub fn expired_claim_cannot_record_a_handler_completion_test() -> Nil {
  use db, queue <- with_queue("squirrel_expired_completion")
  let claim = claimed_task(db, queue)
  set_local(db:, setting: "absurd.fake_now", value: due_time)

  let write =
    sql.complete_run_if_claimed(
      db,
      queue,
      claim.run_id,
      "worker",
      json.string("late result"),
    )

  write
  |> should.equal(Ok(pog.Returned(1, [sql.CompleteRunIfClaimedRow(False)])))
  let assert Ok(pog.Returned(1, [outcome])) =
    sql.get_task_result(db, queue, claim.task_id)
  outcome.state |> should.equal("running")
  outcome.result |> should.equal(None)
}

pub fn fail_run_respects_retry_timestamp_in_non_utc_zone_test() -> Nil {
  use db, queue <- with_queue("squirrel_retry_zone")
  let claim = claimed_task(db, queue)
  let assert Ok(due) = timestamp.parse_rfc3339(due_time)
  set_local(db:, setting: "TimeZone", value: "America/Los_Angeles")

  let assert Ok(_) =
    sql.fail_run_with_retry(
      db,
      queue,
      claim.run_id,
      json.string("failure"),
      due,
    )

  sql.claim_task(db, queue, "worker", 30, 1)
  |> should.equal(Ok(pog.Returned(0, [])))
  set_local(db:, setting: "absurd.fake_now", value: due_time)
  let assert Ok(pog.Returned(1, [retried])) =
    sql.claim_task(db, queue, "worker", 30, 1)
  retried.task_id |> should.equal(claim.task_id)
  retried.attempt |> should.equal(2)
}
