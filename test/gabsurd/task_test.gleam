//// Tests for task lifecycle operations (spawn, claim, complete, fail, cancel).

import gabsurd/client
import gabsurd/event
import gabsurd/lease
import gabsurd/queue
import gabsurd/task
import gabsurd/test_support
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should
import pog
import youid/uuid

pub fn spawn_task_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_spawn")

  let assert Ok(task_info) =
    task.spawn(db, q, "my_task", json.object([]), task.new_options())
  task_info.attempt |> should.equal(1)
  task_info.created |> should.be_true
}

pub fn spawn_with_options_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_spawn_opts")

  let assert Ok(task_info) =
    task.spawn(
      db,
      q,
      "retry_task",
      json.object([#("url", json.string("http://example.com"))]),
      task.new_options()
        |> task.with_max_attempts(3),
    )
  task_info.attempt |> should.equal(1)
  task_info.created |> should.be_true
}

pub fn claim_task_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_claim")

  let assert Ok(task_info) =
    task.spawn(db, q, "claimable_task", json.object([]), task.new_options())
  let assert Ok([claim]) =
    task.claim(db, q, "worker-1", lease.default_expiry, 1)

  claim.task_name |> should.equal("claimable_task")
  claim.attempt |> should.equal(1)
  claim.task_id |> should.equal(task_info.task_id)
  claim.run_id |> should.equal(task_info.run_id)
  claim.retry_strategy |> should.equal(None)
  claim.max_attempts |> should.equal(Some(5))
  claim.headers |> should.equal(None)
  claim.wake_event |> should.equal(None)
  claim.event_payload |> should.equal(None)
}

pub fn default_spawn_options_encode_five_attempts_test() -> Nil {
  let options = task.new_options()

  let encoded = task.encode_options(options)

  json.parse(encoded, max_attempts_decoder()) |> should.equal(Ok(Some(5)))
}

pub fn unlimited_spawn_options_encode_no_attempt_limit_test() -> Nil {
  let options = task.new_options() |> task.with_unlimited_attempts()

  let encoded = task.encode_options(options)

  json.parse(encoded, max_attempts_decoder()) |> should.equal(Ok(None))
}

fn max_attempts_decoder() -> decode.Decoder(Option(Int)) {
  use limit <- decode.optional_field(
    "max_attempts",
    None,
    decode.map(decode.int, Some),
  )
  decode.success(limit)
}

pub fn default_retry_limit_stops_after_five_attempts_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_retry_limit")
  let assert Ok(spawned) =
    task.spawn(db, q, "always_fails", json.null(), task.new_options())

  fail_next_attempt(db:, queue_name: q, attempt: 1)
  fail_next_attempt(db:, queue_name: q, attempt: 2)
  fail_next_attempt(db:, queue_name: q, attempt: 3)
  fail_next_attempt(db:, queue_name: q, attempt: 4)
  fail_next_attempt(db:, queue_name: q, attempt: 5)

  let assert Ok(task.Failed(..)) = task.get_result(db, q, spawned.task_id)
  task.claim(db, q, "worker", lease.default_expiry, 1) |> should.equal(Ok([]))
}

fn fail_next_attempt(
  db db: client.Db,
  queue_name q: String,
  attempt attempt: Int,
) -> Nil {
  let assert Ok([claim]) = task.claim(db, q, "worker", lease.default_expiry, 1)
  claim.attempt |> should.equal(attempt)
  let assert Ok(Nil) = task.fail(db, q, claim.run_id, json.string("failure"))
  Nil
}

pub fn explicit_unlimited_attempts_has_no_limit_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_retry_unlimited")
  let options = task.new_options() |> task.with_unlimited_attempts()

  let assert Ok(_) = task.spawn(db, q, "workflow", json.null(), options)
  let assert Ok([claim]) = task.claim(db, q, "worker", lease.default_expiry, 1)

  claim.max_attempts |> should.equal(None)
}

pub fn complete_run_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_complete")

  let assert Ok(_) =
    task.spawn(db, q, "completable_task", json.object([]), task.new_options())
  let assert Ok(claims) = task.claim(db, q, "worker-2", lease.default_expiry, 1)
  let assert Ok(claim) = list.first(claims)

  task.complete(
    db,
    q,
    claim.run_id,
    json.object([#("status", json.string("done"))]),
  )
  |> should.be_ok
}

pub fn fail_run_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_fail")

  let assert Ok(_) =
    task.spawn(db, q, "failing_task", json.object([]), task.new_options())
  let assert Ok(claims) = task.claim(db, q, "worker-3", lease.default_expiry, 1)
  let assert Ok(claim) = list.first(claims)

  task.fail(db, q, claim.run_id, json.object([#("error", json.string("boom"))]))
  |> should.be_ok
}

pub fn schedule_run_uses_the_database_clock_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("task_schedule_db_time")
  test_support.set_time(db, "2025-01-02T03:04:05Z")
  let assert Ok(_) =
    task.spawn(db, q, "workflow", json.null(), task.new_options())
  let assert Ok([first]) = task.claim(db, q, "worker", lease.default_expiry, 1)

  let outcome = task.schedule_run(db, q, first.run_id, 60)

  outcome |> should.equal(Ok(Nil))
  test_support.set_time(db, "2025-01-02T03:05:04Z")
  task.claim(db, q, "worker", lease.default_expiry, 1) |> should.equal(Ok([]))
  test_support.set_time(db, "2025-01-02T03:05:05Z")
  let assert Ok([resumed]) =
    task.claim(db, q, "worker", lease.default_expiry, 1)
  resumed.run_id |> should.equal(first.run_id)
}

pub fn retry_failed_task_adds_one_attempt_by_default_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_retry")
  let assert Ok(spawned) =
    task.spawn(
      db,
      q,
      "retry_task",
      json.null(),
      task.new_options() |> task.with_max_attempts(1),
    )
  fail_next_attempt(db:, queue_name: q, attempt: 1)

  let assert Ok(retry) =
    task.retry(db, q, spawned.task_id, task.new_retry_options())
  let assert Ok([retried_claim]) =
    task.claim(db, q, "worker", lease.default_expiry, 1)

  retry.task_id |> should.equal(spawned.task_id)
  retry.attempt |> should.equal(2)
  retry.created |> should.be_false
  retried_claim.task_id |> should.equal(retry.task_id)
  retried_claim.run_id |> should.equal(retry.run_id)
  retried_claim.max_attempts |> should.equal(Some(2))
}

pub fn retry_failed_task_sets_explicit_attempt_limit_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_retry_explicit_limit")
  let assert Ok(spawned) =
    task.spawn(
      db,
      q,
      "retry_task",
      json.null(),
      task.new_options() |> task.with_max_attempts(1),
    )
  fail_next_attempt(db:, queue_name: q, attempt: 1)
  let options = task.RetryOptions(max_attempts: Some(4))

  let assert Ok(_) = task.retry(db, q, spawned.task_id, options)
  let assert Ok([claim]) = task.claim(db, q, "worker", lease.default_expiry, 1)

  claim.max_attempts |> should.equal(Some(4))
}

pub fn cancel_task_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_cancel")

  let assert Ok(task_info) =
    task.spawn(db, q, "cancellable_task", json.object([]), task.new_options())
  task.cancel(db, q, task_info.task_id) |> should.be_ok
}

/// Task reads return routing metadata and a variant for each state.
pub fn task_result_states_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_result_states")
  let headers = json.object([#("source", json.string("test"))])

  // pending
  let assert Ok(pending) =
    task.spawn(
      db,
      q,
      "pending_task",
      json.object([]),
      task.new_options() |> task.with_headers(headers),
    )
  task.get_result(db, q, pending.task_id)
  |> should.equal(
    Ok(task.Pending("pending_task", Some("{\"source\": \"test\"}"))),
  )
  let assert Ok(Nil) = task.cancel(db, q, pending.task_id)

  // running
  let assert Ok(running) =
    task.spawn(db, q, "running_task", json.object([]), task.new_options())
  let assert Ok(running_claims) =
    task.claim(db, q, "state-worker", lease.default_expiry, 1)
  let assert Ok(running_claim) = list.first(running_claims)
  running_claim.task_id |> should.equal(running.task_id)
  task.get_result(db, q, running.task_id)
  |> should.equal(Ok(task.Running("running_task", None)))
  let assert Ok(Nil) =
    task.complete(db, q, running_claim.run_id, json.string("running-done"))

  // sleeping
  let assert Ok(sleeping) =
    task.spawn(db, q, "sleeping_task", json.object([]), task.new_options())
  let assert Ok(sleeping_claims) =
    task.claim(db, q, "state-worker", lease.default_expiry, 1)
  let assert Ok(sleeping_claim) = list.first(sleeping_claims)
  let assert Ok(awaited) =
    event.await(
      db,
      q,
      sleeping.task_id,
      sleeping_claim.run_id,
      "state-step",
      "state-event",
      None,
    )
  awaited |> should.equal(event.Suspended)
  task.get_result(db, q, sleeping.task_id)
  |> should.equal(Ok(task.Sleeping("sleeping_task", None)))

  // completed
  let assert Ok(completed) =
    task.spawn(db, q, "completed_task", json.object([]), task.new_options())
  let assert Ok(completed_claims) =
    task.claim(db, q, "state-worker", lease.default_expiry, 1)
  let assert Ok(completed_claim) = list.first(completed_claims)
  let assert Ok(Nil) =
    task.complete(db, q, completed_claim.run_id, json.string("done"))
  task.get_result(db, q, completed.task_id)
  |> should.equal(Ok(task.Completed("completed_task", None, Some("\"done\""))))

  // failed
  let assert Ok(failed) =
    task.spawn(
      db,
      q,
      "failed_task",
      json.object([]),
      task.new_options() |> task.with_max_attempts(1),
    )
  let assert Ok(failed_claims) =
    task.claim(db, q, "state-worker", lease.default_expiry, 1)
  let assert Ok(failed_claim) = list.first(failed_claims)
  let assert Ok(Nil) =
    task.fail(db, q, failed_claim.run_id, json.string("boom"))
  task.get_result(db, q, failed.task_id)
  |> should.equal(Ok(task.Failed("failed_task", None, Some("\"boom\""))))

  // cancelled
  let assert Ok(cancelled) =
    task.spawn(db, q, "cancelled_task", json.object([]), task.new_options())
  let assert Ok(Nil) = task.cancel(db, q, cancelled.task_id)
  task.get_result(db, q, cancelled.task_id)
  |> should.equal(Ok(task.Cancelled("cancelled_task", None)))

  // A task ID from another queue is not found.
  let missing_queue = "test_result_missing"
  let assert Ok(Nil) = queue.create(db, missing_queue)
  task.get_result(db, missing_queue, pending.task_id)
  |> should.equal(Error(client.NotFound))
  task.get_result(db, missing_queue, task.TaskId(uuid.nil))
  |> should.equal(Error(client.NotFound))
}

pub fn completed_task_without_a_payload_has_no_result_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_result_no_payload")
  let assert Ok(spawned) =
    task.spawn(db, q, "workflow", json.null(), task.new_options())
  let assert Ok([claim]) = task.claim(db, q, "worker", lease.default_expiry, 1)
  let task.RunId(run_uuid) = claim.run_id
  // Complete the run with SQL NULL rather than a JSON value.
  let assert Ok(_) =
    pog.query("SELECT absurd.complete_run($1, $2)::text")
    |> pog.parameter(pog.text(q))
    |> pog.parameter(pog.text(uuid.to_string(run_uuid)))
    |> pog.execute(client.connection(db))

  let outcome = task.get_result(db, q, spawned.task_id)

  outcome |> should.equal(Ok(task.Completed("workflow", None, None)))
}

pub fn full_lifecycle_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_lifecycle")

  // 1. Spawn
  let assert Ok(spawned) =
    task.spawn(
      db,
      q,
      "lifecycle_task",
      json.object([#("input", json.int(42))]),
      task.new_options(),
    )
  spawned.attempt |> should.equal(1)

  // 2. Claim
  let assert Ok(claims) =
    task.claim(db, q, "lifecycle-worker", lease.default_expiry, 1)
  list.length(claims) |> should.equal(1)
  let assert Ok(claim) = list.first(claims)
  claim.task_name |> should.equal("lifecycle_task")

  // 3. Complete
  let assert Ok(Nil) =
    task.complete(db, q, claim.run_id, json.object([#("output", json.int(99))]))

  // 4. Verify no more tasks to claim
  let assert Ok(claims2) =
    task.claim(db, q, "lifecycle-worker", lease.default_expiry, 1)
  list.length(claims2) |> should.equal(0)
}
