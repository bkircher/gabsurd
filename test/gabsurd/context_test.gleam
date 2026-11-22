//// Workflow behavior tests based on the Absurd SDK step and event tests.

import gabsurd/client.{type Db}
import gabsurd/context.{type Context}
import gabsurd/event
import gabsurd/lease.{type ClaimExpiry}
import gabsurd/task
import gabsurd/test_support
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleeunit/should
import pog

const claim_start = "2025-01-02T03:04:05Z"

const claim_deadline = "2025-01-02T03:04:35Z"

fn spawn_and_claim(db: Db, queue: String) -> Context {
  let assert Ok(_) =
    task.spawn(db, queue, "workflow", json.null(), task.new_options())
  claim_context(db, queue)
}

fn spawn_and_claim_without_expiry(db: Db, queue: String) -> Context {
  let assert Ok(_) =
    task.spawn(db, queue, "workflow", json.null(), task.new_options())
  claim_as(db:, queue:, owner: "worker", expiry: lease.NoExpiry)
}

fn claim_context(db: Db, queue: String) -> Context {
  claim_as(db:, queue:, owner: "worker", expiry: lease.default_expiry)
}

fn claim_as(
  db db: Db,
  queue queue: String,
  owner claim_owner: String,
  expiry claim_expiry: ClaimExpiry,
) -> Context {
  let assert Ok([claim]) = task.claim(db, queue, claim_owner, claim_expiry, 1)
  context.Context(db:, queue_name: queue, claim:, claim_owner:, claim_expiry:)
}

pub fn step_reuses_checkpoint_after_retry_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_step_replay")
  let first = spawn_and_claim(db, queue)
  let assert Ok(42) =
    context.step(first, "step", decode.int, fn() { json.int(42) })
  let assert Ok(Nil) =
    task.fail(db, queue, context.run_id(first), json.string("retry"))
  let retry = claim_context(db, queue)

  let outcome =
    context.step(retry, "step", decode.int, fn() {
      // nolint: avoid_panic -- fail the test if the retry runs this callback
      panic as "A completed step must not run again"
    })

  outcome |> should.equal(Ok(42))
}

pub fn fresh_step_decode_error_does_not_save_checkpoint_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_step_invalid")
  let ctx = spawn_and_claim(db, queue)

  let outcome =
    context.step(ctx, "step", decode.int, fn() { json.string("not an int") })

  let assert Error(client.CheckpointDecodeError(_)) = outcome
  context.get_checkpoint(ctx, "step") |> should.equal(Ok(None))
}

pub fn replayed_step_returns_a_decode_error_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue(
    "context_step_replay_bad",
  )
  let ctx = spawn_and_claim(db, queue)
  let assert Ok(Nil) =
    context.set_checkpoint(ctx, "step", json.string("old value"))

  let outcome =
    context.step(ctx, "step", decode.int, fn() {
      // nolint: avoid_panic -- fail the test if a decode error runs the callback
      panic as "A saved step must not run again if its decoder fails"
    })

  let assert Error(client.CheckpointDecodeError(_)) = outcome
  Nil
}

pub fn step_does_not_repeat_a_checkpoint_without_json_state_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_step_sql_null")
  let ctx = spawn_and_claim(db, queue)
  let assert Ok(Nil) = context.set_checkpoint(ctx, "step", json.int(42))
  let assert Ok(_) =
    pog.query("UPDATE absurd.c_context_step_sql_null SET state = NULL")
    |> pog.execute(client.connection(db))

  let outcome =
    context.step(ctx, "step", decode.int, fn() {
      // nolint: avoid_panic -- a committed checkpoint must prevent re-execution
      panic as "A completed step must not run again"
    })

  outcome
  |> should.equal(
    Error(client.QueryError("checkpoint has no saved state: step")),
  )
}

pub fn failed_step_returns_application_error_and_runs_again_on_retry_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_fallible_step")
  let first = spawn_and_claim(db, queue)

  let outcome =
    context.try_step(first, "step", decode.int, fn() {
      Error("service unavailable")
    })

  outcome |> should.equal(Error(context.StepFailed("service unavailable")))
  context.get_checkpoint(first, "step") |> should.equal(Ok(None))

  let assert Ok(Nil) =
    task.fail(db, queue, context.run_id(first), json.string("retry"))
  let retry = claim_context(db, queue)

  context.try_step(retry, "step", decode.int, fn() { Ok(json.int(7)) })
  |> should.equal(Ok(7))
}

pub fn fallible_step_reports_decode_errors_as_sdk_errors_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_try_step_bad")
  let ctx = spawn_and_claim(db, queue)

  let outcome =
    context.try_step(ctx, "step", decode.int, fn() {
      Ok(json.string("not an int"))
    })

  let assert Error(context.StepSdkError(client.CheckpointDecodeError(_))) =
    outcome
  context.get_checkpoint(ctx, "step") |> should.equal(Ok(None))
}

pub fn step_cannot_save_a_checkpoint_at_lease_expiry_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_expired_step")
  test_support.set_time(db, claim_start)
  let ctx = spawn_and_claim(db, queue)

  let outcome =
    context.step(ctx, "step", decode.int, fn() {
      test_support.set_time(db, claim_deadline)
      json.int(42)
    })

  outcome |> should.equal(Error(client.ClaimLost))
  context.get_checkpoint(ctx, "step") |> should.equal(Ok(None))
  let assert Ok([retry]) =
    task.claim(db, queue, "worker-2", lease.default_expiry, 1)
  retry.attempt |> should.equal(2)
}

pub fn heartbeat_cannot_renew_an_expired_lease_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_expired_lease")
  test_support.set_time(db, claim_start)
  let ctx = spawn_and_claim(db, queue)
  test_support.set_time(db, claim_deadline)

  let outcome = context.heartbeat(ctx)

  outcome |> should.equal(Error(client.ClaimLost))
  let assert Ok([retry]) =
    task.claim(db, queue, "worker-2", lease.default_expiry, 1)
  retry.attempt |> should.equal(2)
}

pub fn old_claim_cannot_change_a_resumed_run_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_old_claim")
  test_support.set_time(db, claim_start)
  let old = spawn_and_claim(db, queue)
  let assert Ok(event.Suspended) = context.await_event(old, "ready", Some(0))
  test_support.set_time(db, "2025-01-02T03:04:10Z")
  let resumed =
    claim_as(db:, queue:, owner: "worker-2", expiry: lease.default_expiry)
  let assert True = context.run_id(resumed) == context.run_id(old)
  let assert Ok(Nil) = context.set_checkpoint(resumed, "step", json.int(7))
  test_support.set_time(db, "2025-01-02T03:04:20Z")

  let checkpoint = context.set_checkpoint(old, "step", json.int(42))
  let heartbeat = context.heartbeat(old)

  checkpoint |> should.equal(Error(client.ClaimLost))
  heartbeat |> should.equal(Error(client.ClaimLost))
  context.get_checkpoint(resumed, "step") |> should.equal(Ok(Some("7")))
  test_support.set_time(db, "2025-01-02T03:04:40Z")
  let assert Ok([retry]) =
    task.claim(db, queue, "worker-3", lease.default_expiry, 1)
  retry.attempt |> should.equal(2)
}

pub fn heartbeat_extends_an_active_lease_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_active_lease")
  test_support.set_time(db, claim_start)
  let ctx = spawn_and_claim(db, queue)
  test_support.set_time(db, "2025-01-02T03:04:25Z")

  let outcome = context.heartbeat(ctx)

  outcome |> should.equal(Ok(Nil))
  test_support.set_time(db, claim_deadline)
  task.claim(db, queue, "worker-2", lease.default_expiry, 1)
  |> should.equal(Ok([]))
}

pub fn claim_without_expiry_can_save_a_checkpoint_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_no_expiry")
  test_support.set_time(db, claim_start)
  let ctx = spawn_and_claim_without_expiry(db, queue)
  test_support.set_time(db, "2025-01-03T03:04:05Z")

  let outcome = context.set_checkpoint(ctx, "step", json.int(42))

  outcome |> should.equal(Ok(Nil))
  context.get_checkpoint(ctx, "step") |> should.equal(Ok(Some("42")))
}

pub fn heartbeat_checks_a_claim_without_adding_a_deadline_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue(
    "context_no_expiry_heartbeat",
  )
  test_support.set_time(db, claim_start)
  let ctx = spawn_and_claim_without_expiry(db, queue)

  let outcome = context.heartbeat(ctx)
  // Move beyond any deadline that fits in the SQL integer lease range.
  test_support.set_time(db, "2100-01-02T03:04:05Z")
  let later = context.heartbeat(ctx)

  outcome |> should.equal(Ok(Nil))
  later |> should.equal(Ok(Nil))
}

pub fn heartbeat_without_expiry_rejects_an_old_claim_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue(
    "context_no_expiry_stale",
  )
  let old = spawn_and_claim_without_expiry(db, queue)
  let assert Ok(event.Suspended) = context.await_event(old, "ready", None)
  let assert Ok(Nil) = event.emit(db, queue, "ready", json.null())
  let _resumed =
    claim_as(db:, queue:, owner: "worker-2", expiry: lease.NoExpiry)

  let outcome = context.heartbeat(old)

  outcome |> should.equal(Error(client.ClaimLost))
}

pub fn cancelled_task_heartbeat_returns_task_cancelled_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_cancelled")
  let ctx = spawn_and_claim(db, queue)
  let assert Ok(Nil) = task.cancel(db, queue, context.task_id(ctx))

  let outcome = context.heartbeat(ctx)

  outcome |> should.equal(Error(client.TaskCancelled))
}

pub fn failed_run_heartbeat_reports_a_conflict_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_failed_run")
  let ctx = spawn_and_claim(db, queue)
  let assert Ok(Nil) =
    task.fail(db, queue, context.run_id(ctx), json.string("retry"))

  let outcome = context.heartbeat(ctx)

  let assert Error(client.RunAlreadyFailed(_)) = outcome
  Nil
}

pub fn event_wait_cannot_suspend_an_expired_claim_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_wait_expired")
  test_support.set_time(db, claim_start)
  let ctx = spawn_and_claim(db, queue)
  test_support.set_time(db, claim_deadline)

  let outcome = context.await_event(ctx, "ready", Some(60))

  outcome |> should.equal(Error(client.ClaimLost))
  let assert Ok([retry]) =
    task.claim(db, queue, "worker-2", lease.default_expiry, 1)
  retry.attempt |> should.equal(2)
}

pub fn event_wait_cannot_suspend_a_newer_claim_on_the_same_run_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_wait_old")
  test_support.set_time(db, claim_start)
  let old = spawn_and_claim(db, queue)
  let assert Ok(event.Suspended) = context.await_event(old, "ready", None)
  let assert Ok(Nil) = event.emit(db, queue, "ready", json.null())
  let resumed =
    claim_as(db:, queue:, owner: "worker-2", expiry: lease.default_expiry)

  let outcome = context.await_event(old, "next", None)

  context.run_id(resumed) |> should.equal(context.run_id(old))
  outcome |> should.equal(Error(client.ClaimLost))
  context.heartbeat(resumed) |> should.equal(Ok(Nil))
}

pub fn event_wait_cannot_save_a_payload_after_lease_expiry_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_event_expired")
  test_support.set_time(db, claim_start)
  let ctx = spawn_and_claim(db, queue)
  let assert Ok(Nil) = event.emit(db, queue, "ready", json.int(42))
  test_support.set_time(db, claim_deadline)

  let outcome = context.await_event(ctx, "ready", None)

  outcome |> should.equal(Error(client.ClaimLost))
  context.get_checkpoint(ctx, "$await:ready") |> should.equal(Ok(None))
}

pub fn unlimited_wait_stays_sleeping_until_an_event_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_wait_unlimited")
  test_support.set_time(db, "2025-01-02T03:04:05Z")
  let first = spawn_and_claim(db, queue)

  let assert Ok(event.Suspended) = context.await_event(first, "ready", None)
  test_support.set_time(db, "2025-01-03T03:04:05Z")

  task.claim(db, queue, "worker", lease.default_expiry, 1)
  |> should.equal(Ok([]))
  let assert Ok(Nil) = event.emit(db, queue, "ready", json.null())
  let resumed = claim_context(db, queue)
  context.run_id(resumed) |> should.equal(context.run_id(first))
  context.await_event(resumed, "ready", None)
  |> should.equal(Ok(event.Received("null")))
}

pub fn timed_wait_returns_timed_out_after_the_deadline_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_wait_timeout")
  test_support.set_time(db, "2025-01-02T03:04:05Z")
  let first = spawn_and_claim(db, queue)
  let assert Ok(event.Suspended) = context.await_event(first, "ready", Some(15))
  test_support.set_time(db, "2025-01-02T03:04:19Z")
  task.claim(db, queue, "worker", lease.default_expiry, 1)
  |> should.equal(Ok([]))

  test_support.set_time(db, "2025-01-02T03:04:20Z")
  let resumed = claim_context(db, queue)
  let outcome = context.await_event(resumed, "ready", Some(15))

  context.run_id(resumed) |> should.equal(context.run_id(first))
  outcome |> should.equal(Ok(event.TimedOut))
}

pub fn consecutive_timed_waits_preserve_the_first_timeout_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_wait_sequence")
  test_support.set_time(db, "2025-01-02T03:04:05Z")
  let first = spawn_and_claim(db, queue)

  context.await_event(first, "a", Some(15))
  |> should.equal(Ok(event.Suspended))

  test_support.set_time(db, "2025-01-02T03:04:20Z")
  let after_first_deadline = claim_context(db, queue)

  context.await_event(after_first_deadline, "a", Some(15))
  |> should.equal(Ok(event.TimedOut))
  context.await_event(after_first_deadline, "b", Some(15))
  |> should.equal(Ok(event.Suspended))

  test_support.set_time(db, "2025-01-02T03:04:35Z")
  let after_second_deadline = claim_context(db, queue)

  context.await_event(after_second_deadline, "a", Some(15))
  |> should.equal(Ok(event.TimedOut))
  context.await_event(after_second_deadline, "b", Some(15))
  |> should.equal(Ok(event.TimedOut))
}

pub fn late_event_does_not_override_timeout_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_wait_late")
  test_support.set_time(db, "2025-01-02T03:04:05Z")
  let first = spawn_and_claim(db, queue)
  let assert Ok(event.Suspended) = context.await_event(first, "ready", Some(15))
  test_support.set_time(db, "2025-01-02T03:04:21Z")
  let assert Ok(Nil) = event.emit(db, queue, "ready", json.string("late"))

  let resumed = claim_context(db, queue)
  let outcome = context.await_event(resumed, "ready", Some(15))

  context.run_id(resumed) |> should.equal(context.run_id(first))
  outcome |> should.equal(Ok(event.TimedOut))
}

pub fn timeout_survives_failure_before_wait_replay_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_timeout_retry")
  test_support.set_time(db, claim_start)
  let first = spawn_and_claim(db, queue)
  let assert Ok(event.Suspended) = context.await_event(first, "ready", Some(15))
  test_support.set_time(db, "2025-01-02T03:04:20Z")
  let resumed = claim_context(db, queue)
  let assert Ok(Nil) =
    task.fail(db, queue, context.run_id(resumed), json.string("handler failed"))
  test_support.set_time(db, "2025-01-02T03:04:21Z")
  let assert Ok(Nil) = event.emit(db, queue, "ready", json.string("late"))
  let retry = claim_context(db, queue)

  let outcome = context.await_event(retry, "ready", Some(15))

  context.attempt(retry) |> should.equal(2)
  outcome |> should.equal(Ok(event.TimedOut))
}

pub fn event_before_deadline_stays_received_after_deadline_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_wait_on_time")
  test_support.set_time(db, claim_start)
  let first = spawn_and_claim(db, queue)
  let assert Ok(event.Suspended) = context.await_event(first, "ready", Some(15))
  test_support.set_time(db, "2025-01-02T03:04:19Z")
  let assert Ok(Nil) = event.emit(db, queue, "ready", json.null())
  test_support.set_time(db, "2025-01-02T03:04:21Z")
  let resumed = claim_context(db, queue)

  let outcome = context.await_event(resumed, "ready", Some(15))

  outcome |> should.equal(Ok(event.Received("null")))
}

pub fn zero_second_wait_can_resume_immediately_test() -> Nil {
  use db, queue <- test_support.with_transaction_queue("context_wait_zero")
  test_support.set_time(db, "2025-01-02T03:04:05Z")
  let first = spawn_and_claim(db, queue)

  let first_wait = context.await_event(first, "ready", Some(0))
  let resumed = claim_context(db, queue)
  let second_wait = context.await_event(resumed, "ready", Some(0))

  first_wait |> should.equal(Ok(event.Suspended))
  second_wait |> should.equal(Ok(event.TimedOut))
}
