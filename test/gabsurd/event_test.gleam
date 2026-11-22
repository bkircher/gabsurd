//// Tests for event operations (emit, await).

import gabsurd/client
import gabsurd/event
import gabsurd/lease
import gabsurd/task
import gabsurd/test_support
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should
import pog

pub fn emit_event_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_emit_event")

  // Emit should succeed even with no listeners
  event.emit(db, q, "test_event", json.object([#("key", json.string("value"))]))
  |> should.be_ok
}

pub fn emit_event_null_payload_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_emit_null")

  // Emit with JSON null payload
  event.emit(db, q, "null_event", json.null())
  |> should.be_ok
}

pub fn emit_invalid_event_returns_database_error_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_emit_invalid")

  let outcome = event.emit(db, q, "", json.null())

  outcome
  |> should.equal(
    Error(client.PostgresqlError(
      sqlstate: "P0001",
      name: "raise_exception",
      message: "event_name must be provided",
    )),
  )
}

pub fn emit_reports_the_violated_constraint_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_emit_constraint")
  let assert Ok(_) =
    pog.query(
      "ALTER TABLE absurd.e_test_emit_constraint
       ADD CONSTRAINT reject_event CHECK (event_name <> 'forbidden')",
    )
    |> pog.execute(client.connection(db))

  let outcome = event.emit(db, q, "forbidden", json.null())

  let assert Error(client.ConstraintViolated(constraint: "reject_event", ..)) =
    outcome
  Nil
}

/// A wait suspends the run when the event is missing.
pub fn await_event_no_event_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_await_noevent")

  // Spawn + claim to get task/run IDs
  let assert Ok(spawned) =
    task.spawn(db, q, "awaiting_task", json.object([]), task.new_options())
  let assert Ok(claims) =
    task.claim(db, q, "await-worker", lease.default_expiry, 1)
  let assert Ok(claim) = list.first(claims)

  let outcome =
    event.await(
      db,
      q,
      spawned.task_id,
      claim.run_id,
      "step1",
      "my_event",
      Some(1),
    )

  outcome |> should.equal(Ok(event.Suspended))
}

pub fn timed_wait_rejects_a_run_from_another_task_test() -> Nil {
  check_wait_rejects_a_run_from_another_task(
    "test_timed_wait_wrong_task",
    Some(30),
  )
}

pub fn unlimited_wait_rejects_a_run_from_another_task_test() -> Nil {
  check_wait_rejects_a_run_from_another_task(
    "test_unlimited_wait_wrong_task",
    None,
  )
}

fn check_wait_rejects_a_run_from_another_task(
  queue: String,
  timeout: Option(Int),
) -> Nil {
  use db, q <- test_support.with_transaction_queue(queue)
  let assert Ok(_) =
    task.spawn(db, q, "run_task", json.null(), task.new_options())
  let assert Ok([claim]) = task.claim(db, q, "worker", lease.default_expiry, 1)
  let assert Ok(other) =
    task.spawn(db, q, "other_task", json.null(), task.new_options())

  let outcome =
    event.await(db, q, other.task_id, claim.run_id, "step", "ready", timeout)

  let assert Error(client.PostgresqlError(sqlstate: "P0001", ..)) = outcome
  Nil
}

/// Test emit-then-await: emit event first, then await should find it
pub fn emit_then_await_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_emit_await")

  let assert Ok(spawned) =
    task.spawn(db, q, "event_task", json.object([]), task.new_options())
  let assert Ok(claims) =
    task.claim(db, q, "event-worker", lease.default_expiry, 1)
  let assert Ok(claim) = list.first(claims)

  // Emit the event first
  let assert Ok(Nil) =
    event.emit(db, q, "expected_event", json.object([#("data", json.int(42))]))

  let outcome =
    event.await(
      db,
      q,
      spawned.task_id,
      claim.run_id,
      "step1",
      "expected_event",
      Some(5),
    )

  outcome |> should.equal(Ok(event.Received("{\"data\": 42}")))
}

pub fn await_event_reports_timeout_when_the_event_is_missing_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_await_timeout")
  let assert Ok(_) =
    task.spawn(db, q, "workflow", json.null(), task.new_options())
  let assert Ok([first]) = task.claim(db, q, "worker", lease.default_expiry, 1)
  let assert Ok(event.Suspended) =
    event.await(db, q, first.task_id, first.run_id, "step", "ready", Some(0))
  let assert Ok([resumed]) =
    task.claim(db, q, "worker", lease.default_expiry, 1)

  let outcome =
    event.await(
      db,
      q,
      resumed.task_id,
      resumed.run_id,
      "step",
      "ready",
      Some(0),
    )

  resumed.wake_event |> should.equal(Some("ready"))
  resumed.event_payload |> should.equal(None)
  outcome |> should.equal(Ok(event.TimedOut))
}

pub fn late_event_does_not_override_low_level_timeout_on_retry_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_await_late")
  test_support.set_time(db, "2025-01-02T03:04:05Z")
  let assert Ok(_) =
    task.spawn(db, q, "workflow", json.null(), task.new_options())
  let assert Ok([first]) = task.claim(db, q, "worker", lease.default_expiry, 1)
  let assert Ok(event.Suspended) =
    event.await(db, q, first.task_id, first.run_id, "step", "ready", Some(15))
  test_support.set_time(db, "2025-01-02T03:04:20Z")
  let assert Ok(Nil) = event.emit(db, q, "ready", json.string("late"))
  let assert Ok([resumed]) =
    task.claim(db, q, "worker", lease.default_expiry, 1)
  let assert Ok(Nil) =
    task.fail(db, q, resumed.run_id, json.string("retry before replay"))
  let assert Ok([retry]) = task.claim(db, q, "worker", lease.default_expiry, 1)

  let outcome =
    event.await(db, q, retry.task_id, retry.run_id, "step", "ready", None)

  outcome |> should.equal(Ok(event.TimedOut))
}

pub fn a_new_step_can_wait_for_the_same_event_after_a_timeout_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_await_next_step")
  test_support.set_time(db, "2025-01-02T03:04:05Z")
  let assert Ok(_) =
    task.spawn(db, q, "workflow", json.null(), task.new_options())
  let assert Ok([first]) = task.claim(db, q, "worker", lease.default_expiry, 1)
  let assert Ok(event.Suspended) =
    event.await(db, q, first.task_id, first.run_id, "first", "ready", Some(0))
  let assert Ok([resumed]) =
    task.claim(db, q, "worker", lease.default_expiry, 1)

  let outcome =
    event.await(db, q, resumed.task_id, resumed.run_id, "second", "ready", None)

  outcome |> should.equal(Ok(event.Suspended))
}

pub fn await_event_receives_json_null_after_suspension_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_await_json_null")
  let assert Ok(_) =
    task.spawn(db, q, "workflow", json.null(), task.new_options())
  let assert Ok([first]) = task.claim(db, q, "worker", lease.default_expiry, 1)
  let assert Ok(event.Suspended) =
    event.await(db, q, first.task_id, first.run_id, "step", "ready", None)
  let assert Ok(Nil) = event.emit(db, q, "ready", json.null())
  let assert Ok([resumed]) =
    task.claim(db, q, "worker", lease.default_expiry, 1)

  let outcome =
    event.await(db, q, resumed.task_id, resumed.run_id, "step", "ready", None)

  resumed.wake_event |> should.equal(None)
  resumed.event_payload |> should.equal(Some("null"))
  outcome |> should.equal(Ok(event.Received("null")))
}
