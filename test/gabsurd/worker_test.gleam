//// Tests for the OTP worker actor.

import gabsurd/client
import gabsurd/context
import gabsurd/event
import gabsurd/lease
import gabsurd/queue
import gabsurd/task
import gabsurd/test_support
import gabsurd/worker.{type Handler, type HandlerResult, Complete, Fail, Handler}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/string
import gleeunit/should
import pog
import youid/uuid

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

fn delay_ms(milliseconds: Int) -> worker.DelayMs {
  let assert Ok(delay) = worker.delay_ms(milliseconds)
  delay
}

/// Track how many times a handler is called, using process subject.
fn tracking_handler(
  task_name: String,
  tracker: process.Subject(Nil),
) -> Handler {
  Handler(
    task_name: task_name,
    execute: fn(_ctx) {
      process.send(tracker, Nil)
      Complete(json.object([#("tracked", json.bool(True))]))
    },
    on_error: option.None,
  )
}

fn blocking_handler(tracker: process.Subject(process.Subject(Nil))) -> Handler {
  Handler(
    task_name: "block",
    execute: fn(_) {
      let release = process.new_subject()
      process.send(tracker, release)
      let assert Ok(Nil) = process.receive(release, 5000)
      Complete(json.null())
    },
    on_error: option.None,
  )
}

fn setup(queue_name: String) -> #(client.Db, String) {
  let name = queue_name <> "_" <> string.slice(uuid.v4_string(), 0, 8)
  let assert Ok(started) = client.start(test_support.database_url())
  let db = started.data
  let assert Ok(Nil) = queue.create(db, name)
  #(db, name)
}

fn teardown(db: client.Db, queue_name: String) -> Nil {
  let _ = queue.drop(db, queue_name)
  process.send_exit(db.pid)
}

fn expect_worker_stop(w: worker.Worker) -> Nil {
  worker.stop_and_wait(w, 5000) |> should.equal(Ok(Nil))
}

fn await_exit(monitor: process.Monitor) -> Result(process.ExitReason, Nil) {
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(down) { down.reason })
  |> process.selector_receive(5000)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Worker should claim a task, execute the handler, and complete it.
pub fn worker_claims_and_completes_task_test() -> Nil {
  let #(db, q) = setup("test_worker_claim")

  // Spawn a task
  let assert Ok(spawned) =
    task.spawn(db, q, "ok_task", json.object([]), task.new_options())

  let checkpoints = process.new_subject()
  let handler =
    Handler(
      task_name: "ok_task",
      execute: fn(ctx) {
        let saved = context.set_checkpoint(ctx, "step", json.int(42))
        process.send(checkpoints, saved)
        Complete(json.int(42))
      },
      on_error: option.None,
    )
  let config =
    worker.new(db, q, [handler])
    |> worker.with_poll_interval(delay_ms(100))

  let assert Ok(started) = worker.start(config)
  let running_worker = started.data

  process.receive(checkpoints, 5000) |> should.equal(Ok(Ok(Nil)))

  expect_worker_stop(running_worker)

  let assert Ok(task.Completed(result: option.Some("42"), ..)) =
    task.get_result(db, q, spawned.task_id)

  teardown(db, q)
}

/// Worker should fail a task when the handler returns Fail.
pub fn worker_fails_task_on_handler_error_test() -> Nil {
  let #(db, q) = setup("test_worker_fail")

  // One attempt means the worker does not retry this task.
  let assert Ok(spawned) =
    task.spawn(
      db,
      q,
      "fail_task",
      json.object([]),
      task.new_options() |> task.with_max_attempts(1),
    )

  let tracker = process.new_subject()
  // A handler for fail_task that tracks when called, then returns error
  let handler =
    Handler(
      task_name: "fail_task",
      execute: fn(_ctx) {
        process.send(tracker, Nil)
        Fail(json.object([#("deliberate", json.bool(True))]))
      },
      on_error: option.None,
    )

  let config =
    worker.new(db, q, [handler])
    |> worker.with_poll_interval(delay_ms(100))

  let assert Ok(started) = worker.start(config)
  let running_worker = started.data
  let assert Ok(Nil) = process.receive(tracker, 5000)

  expect_worker_stop(running_worker)

  let assert Ok(task.Failed(..)) = task.get_result(db, q, spawned.task_id)

  teardown(db, q)
}

/// A worker with three slots can process three tasks.
pub fn worker_processes_multiple_tasks_test() -> Nil {
  let #(db, q) = setup("test_worker_multi")

  // Spawn 3 tasks
  let assert Ok(_) =
    task.spawn(db, q, "ok_task", json.object([]), task.new_options())
  let assert Ok(_) =
    task.spawn(db, q, "ok_task", json.object([]), task.new_options())
  let assert Ok(_) =
    task.spawn(db, q, "ok_task", json.object([]), task.new_options())

  let tracker = process.new_subject()
  let handler = tracking_handler("ok_task", tracker)

  let config =
    worker.new(db, q, [handler])
    |> worker.with_poll_interval(delay_ms(100))
    |> worker.with_batch_size(3)

  let assert Ok(started) = worker.start(config)
  let running_worker = started.data

  // Wait for all 3 tasks to be processed
  let assert Ok(Nil) = process.receive(tracker, 5000)
  let assert Ok(Nil) = process.receive(tracker, 5000)
  let assert Ok(Nil) = process.receive(tracker, 5000)

  expect_worker_stop(running_worker)
  let assert Ok(claims) =
    task.claim(db, q, "verify_worker", lease.default_expiry, 10)
  claims |> should.equal([])

  teardown(db, q)
}

pub fn worker_keeps_polling_without_claiming_more_than_its_free_slots_test() -> Nil {
  let #(db, q) = setup("worker_free_slots")
  let tracker = process.new_subject()
  let handler =
    Handler(
      task_name: "blocked",
      execute: fn(ctx) {
        let release = process.new_subject()
        process.send(tracker, #(context.task_id(ctx), release))
        let assert Ok(Nil) = process.receive(release, 5000)
        Complete(json.null())
      },
      on_error: option.None,
    )
  let assert Ok(first) =
    task.spawn(db, q, "blocked", json.null(), task.new_options())
  let assert Ok(started) =
    worker.new(db, q, [handler])
    |> worker.with_batch_size(2)
    |> worker.with_poll_interval(delay_ms(20))
    |> worker.start
  let assert Ok(#(first_id, release_first)) = process.receive(tracker, 2000)
  first_id |> should.equal(first.task_id)
  // Make both tasks ready in the same transaction. Only one slot is free.
  let assert Ok(#(second, third)) =
    pog.transaction(client.connection(db), fn(connection) {
      let tx = client.Db(..db, connection:)
      let assert Ok(second) =
        task.spawn(tx, q, "blocked", json.null(), task.new_options())
      let assert Ok(third) =
        task.spawn(tx, q, "blocked", json.null(), task.new_options())
      Ok(#(second, third))
    })

  let assert Ok(#(second_id, release_second)) = process.receive(tracker, 2000)
  let assert Ok(task.Pending(..)) = task.get_result(db, q, third.task_id)
  second_id |> should.equal(second.task_id)

  process.send(release_second, Nil)

  let assert Ok(#(third_id, release_third)) = process.receive(tracker, 2000)
  third_id |> should.equal(third.task_id)
  let assert Ok(task.Running(..)) = task.get_result(db, q, first.task_id)

  process.send(release_first, Nil)
  process.send(release_third, Nil)
  expect_worker_stop(started.data)
  teardown(db, q)
}

pub fn worker_reuses_a_slot_without_waiting_for_the_next_lease_check_test() -> Nil {
  let #(db, q) = setup("worker_slot_reuse")
  let blocked = process.new_subject()
  let next = process.new_subject()
  let assert Ok(_) = task.spawn(db, q, "block", json.null(), task.new_options())
  let assert Ok(started) =
    worker.new(db, q, [
      blocking_handler(blocked),
      tracking_handler("next", next),
    ])
    |> worker.with_poll_interval(delay_ms(1000))
    |> worker.start
  let assert Ok(release) = process.receive(blocked, 5000)
  let assert Ok(_) = task.spawn(db, q, "next", json.null(), task.new_options())

  process.send(release, Nil)

  process.receive(next, 750) |> should.equal(Ok(Nil))
  expect_worker_stop(started.data)
  teardown(db, q)
}

pub fn worker_recovers_from_a_blocked_handler_without_another_worker_test() -> Nil {
  let #(db, q) = setup("worker_claim_timeout")
  let blocked = process.new_subject()
  let retried = process.new_subject()
  let backlog = process.new_subject()
  let handler =
    Handler(
      task_name: "block_first_attempt",
      execute: fn(ctx) {
        case context.attempt(ctx) {
          1 -> {
            process.trap_exits(True)
            process.send(blocked, process.self())
            process.sleep_forever()
            Complete(json.null())
          }
          attempt -> {
            process.send(retried, Nil)
            Complete(json.int(attempt))
          }
        }
      },
      on_error: option.None,
    )
  let assert Ok(first) =
    task.spawn(
      db,
      q,
      "block_first_attempt",
      json.null(),
      task.new_options() |> task.with_max_attempts(2),
    )
  let assert Ok(started) =
    worker.new(db, q, [handler, tracking_handler("backlog", backlog)])
    |> worker.with_poll_interval(delay_ms(20))
    |> worker.start
  let assert Ok(pid) = process.receive(blocked, 2000)
  let monitor = process.monitor(pid)
  let assert Ok(second) =
    task.spawn(db, q, "backlog", json.null(), task.new_options())

  let task.RunId(run_id) = first.run_id
  // Move the database deadline forward without waiting for the full lease.
  let assert Ok(pog.Returned(1, _)) =
    pog.query(
      "UPDATE absurd.\"r_"
      <> q
      <> "\" SET claim_expires_at = absurd.current_time() WHERE run_id = $1",
    )
    |> pog.parameter(pog.text(uuid.to_string(run_id)))
    |> pog.execute(client.connection(db))

  await_exit(monitor) |> should.equal(Ok(process.Killed))
  process.receive(backlog, 2000) |> should.equal(Ok(Nil))
  process.receive(retried, 2000) |> should.equal(Ok(Nil))
  expect_worker_stop(started.data)
  let assert Ok(task.Completed(result: option.Some("2"), ..)) =
    task.get_result(db, q, first.task_id)
  let assert Ok(task.Completed(..)) = task.get_result(db, q, second.task_id)

  let assert Ok(pog.Returned(1, ["$ClaimTimeout"])) =
    pog.query(
      "SELECT failure_reason->>'name' FROM absurd.\"r_"
      <> q
      <> "\" WHERE run_id = $1",
    )
    |> pog.parameter(pog.text(uuid.to_string(run_id)))
    |> pog.returning(decode.at([0], decode.string))
    |> pog.execute(client.connection(db))
  teardown(db, q)
}

pub fn worker_keeps_a_handler_past_its_original_lease_after_a_heartbeat_test() -> Nil {
  let #(db, q) = setup("worker_renewed_lease")
  let finished = process.new_subject()
  let handler =
    Handler(
      task_name: "renew",
      execute: fn(ctx) {
        // Keep the first attempt alive longer than its two-second lease.
        int.range(from: 0, to: 12, with: Nil, run: fn(_, _) {
          process.sleep(200)
          let assert Ok(Nil) = context.heartbeat(ctx)
          Nil
        })
        process.send(finished, Nil)
        Complete(json.int(context.attempt(ctx)))
      },
      on_error: option.None,
    )
  let assert Ok(first) =
    task.spawn(
      db,
      q,
      "renew",
      json.null(),
      task.new_options() |> task.with_max_attempts(1),
    )
  let assert Ok(seconds) = lease.seconds(2)
  let assert Ok(started) =
    worker.new(db, q, [handler])
    |> worker.with_claim_expiry(lease.ExpiresAfter(seconds))
    |> worker.with_poll_interval(delay_ms(20))
    |> worker.start

  process.receive(finished, 5000) |> should.equal(Ok(Nil))
  expect_worker_stop(started.data)

  let assert Ok(task.Completed(result: option.Some("1"), ..)) =
    task.get_result(db, q, first.task_id)
  teardown(db, q)
}

pub fn worker_continues_after_a_handler_panics_test() -> Nil {
  let #(db, q) = setup("worker_handler_panic")
  let ready = process.new_subject()
  let tracker = process.new_subject()
  let handler =
    Handler(
      task_name: "crash",
      execute: fn(_) {
        process.send(ready, Nil)
        // nolint: avoid_panic -- exercise worker recovery after a handler crash
        panic as "Deliberate handler panic"
      },
      on_error: option.None,
    )
  let assert Ok(started) =
    worker.new(db, q, [handler, tracking_handler("ok", tracker)])
    |> worker.with_claim_expiry(lease.NoExpiry)
    |> worker.with_poll_interval(delay_ms(20))
    |> worker.start
  process.unlink(started.pid)
  let assert Ok(crashing) =
    task.spawn(
      db,
      q,
      "crash",
      json.null(),
      task.new_options() |> task.with_max_attempts(1),
    )
  let assert Ok(Nil) = process.receive(ready, 2000)

  let assert Ok(_) = task.spawn(db, q, "ok", json.null(), task.new_options())

  let assert Ok(Nil) = process.receive(tracker, 2000)
  let assert Ok(task.Failed(..)) = task.get_result(db, q, crashing.task_id)
  expect_worker_stop(started.data)
  teardown(db, q)
}

pub fn worker_does_not_fail_a_newer_claim_when_the_old_handler_panics_test() -> Nil {
  check_new_claim_survives_old_handler("worker_stale_crash", fn() {
    // nolint: avoid_panic -- crash the old handler after a new claim
    panic as "Deliberate panic after suspension"
  })
}

pub fn worker_ignores_completion_from_an_old_claim_test() -> Nil {
  check_new_claim_survives_old_handler("worker_stale_complete", fn() {
    Complete(json.string("old claim"))
  })
}

pub fn worker_ignores_failure_from_an_old_claim_test() -> Nil {
  check_new_claim_survives_old_handler("worker_stale_fail", fn() {
    Fail(json.string("old claim"))
  })
}

fn check_new_claim_survives_old_handler(
  queue_name: String,
  old_handler_result: fn() -> HandlerResult,
) -> Nil {
  let #(db, q) = setup(queue_name)
  let waits = process.new_subject()
  let marker = process.new_subject()
  let handler =
    Handler(
      task_name: "wait",
      execute: fn(ctx) {
        let release = process.new_subject()
        let outcome = context.await_event(ctx, "ready", option.None)
        process.send(waits, #(outcome, context.run_id(ctx), release))
        let assert Ok(Nil) = process.receive(release, 5000)
        case outcome {
          Ok(event.Suspended) -> old_handler_result()
          Ok(event.Received(_)) -> Complete(json.string("new claim"))
          Ok(event.TimedOut) -> Fail(json.string("This wait has no deadline"))
          Error(error) -> Fail(json.string(client.error_message(error)))
        }
      },
      on_error: option.None,
    )
  let assert Ok(info) =
    task.spawn(
      db,
      q,
      "wait",
      json.null(),
      task.new_options() |> task.with_max_attempts(1),
    )
  let assert Ok(started) =
    worker.new(db, q, [handler, tracking_handler("marker", marker)])
    |> worker.with_batch_size(2)
    |> worker.with_claim_expiry(lease.NoExpiry)
    |> worker.with_poll_interval(delay_ms(20))
    |> worker.start
  let assert Ok(#(Ok(event.Suspended), _, release_old)) =
    process.receive(waits, 2000)
  let assert Ok(Nil) = event.emit(db, q, "ready", json.null())
  let assert Ok(#(Ok(event.Received(_)), run_id, release_new)) =
    process.receive(waits, 2000)
  run_id |> should.equal(info.run_id)
  let assert Ok(_) =
    task.spawn(db, q, "marker", json.null(), task.new_options())

  process.send(release_old, Nil)
  // The marker can run only after the old handler frees its slot.
  let assert Ok(Nil) = process.receive(marker, 2000)
  let after_old = task.get_result(db, q, info.task_id)
  process.send(release_new, Nil)
  expect_worker_stop(started.data)
  let outcome = task.get_result(db, q, info.task_id)
  teardown(db, q)

  let assert Ok(task.Running(..)) = after_old
  let assert Ok(task.Completed(result: option.Some("\"new claim\""), ..)) =
    outcome
  Nil
}

pub fn worker_drains_active_tasks_without_claiming_more_test() -> Nil {
  let #(db, q) = setup("worker_drains")
  let tracker = process.new_subject()
  let handler = blocking_handler(tracker)
  let assert Ok(first) =
    task.spawn(db, q, "block", json.null(), task.new_options())
  let assert Ok(started) =
    worker.new(db, q, [handler])
    |> worker.with_poll_interval(delay_ms(20))
    |> worker.start
  let assert Ok(release) = process.receive(tracker, 2000)
  let assert Ok(second) =
    task.spawn(db, q, "block", json.null(), task.new_options())
  let monitor = process.monitor(started.pid)

  let shutdown = worker.stop_and_wait(started.data, 50)

  shutdown |> should.equal(Error(worker.ShutdownTimedOut))
  process.send(release, Nil)
  await_exit(monitor) |> should.equal(Ok(process.Normal))

  let assert Ok(task.Completed(result: option.Some("null"), ..)) =
    task.get_result(db, q, first.task_id)
  let assert Ok(task.Pending(..)) = task.get_result(db, q, second.task_id)

  teardown(db, q)
}

pub fn worker_kills_exit_trapping_handler_after_supervisor_timeout_test() -> Nil {
  let #(db, q) = setup("worker_forced_shutdown")
  let tracker = process.new_subject()
  let handler =
    Handler(
      task_name: "block",
      execute: fn(_) {
        process.trap_exits(True)
        process.send(tracker, process.self())
        process.sleep_forever()
        Complete(json.null())
      },
      on_error: option.None,
    )
  let assert Ok(_) = task.spawn(db, q, "block", json.null(), task.new_options())
  let config =
    worker.new(db, q, [handler])
    |> worker.with_poll_interval(delay_ms(20))
  let child =
    worker.child_spec(config)
    |> supervision.timeout(50)
  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child)
    |> static_supervisor.start()
  let assert Ok(pid) = process.receive(tracker, 2000)
  let handler_monitor = process.monitor(pid)
  let supervisor_monitor = process.monitor(started.pid)

  process.send_exit(started.pid)
  let supervisor_exit = await_exit(supervisor_monitor)
  let handler_exit = await_exit(handler_monitor)

  // If shutdown did not stop the handler, stop it before teardown.
  process.demonitor_process(handler_monitor)
  process.kill(pid)
  teardown(db, q)
  supervisor_exit |> should.equal(Ok(process.Normal))
  handler_exit |> should.equal(Ok(process.Killed))
}

pub fn worker_cannot_complete_a_task_that_was_cancelled_test() -> Nil {
  let #(db, q) = setup("worker_cancelled")
  let tracker = process.new_subject()
  let assert Ok(spawned) =
    task.spawn(db, q, "block", json.null(), task.new_options())
  let assert Ok(started) =
    worker.new(db, q, [blocking_handler(tracker)])
    |> worker.with_poll_interval(delay_ms(20))
    |> worker.start
  let assert Ok(release) = process.receive(tracker, 2000)
  let assert Ok(Nil) = task.cancel(db, q, spawned.task_id)

  process.send(release, Nil)
  expect_worker_stop(started.data)

  let assert Ok(task.Cancelled(..)) = task.get_result(db, q, spawned.task_id)

  teardown(db, q)
}

/// Worker should defer tasks with no matching handler.
pub fn worker_defers_unknown_task_test() -> Nil {
  let #(db, q) = setup("test_worker_unknown")

  // Unknown tasks are deferred rather than failed, regardless of retries.
  let assert Ok(task_info) =
    task.spawn(
      db,
      q,
      "unknown_task",
      json.object([]),
      task.new_options() |> task.with_max_attempts(1),
    )

  let tracker = process.new_subject()
  let handler = tracking_handler("ok_task", tracker)

  let config =
    worker.new(db, q, [handler])
    |> worker.with_poll_interval(delay_ms(100))

  let assert Ok(started) = worker.start(config)
  let running_worker = started.data

  // Wait a bit for the poll cycle to run
  process.sleep(1000)

  // The unknown task should be sleeping until its deferred retry.
  let assert Ok(task.Sleeping(..)) = task.get_result(db, q, task_info.task_id)

  expect_worker_stop(running_worker)
  teardown(db, q)
}

/// Worker pool with multiple workers should process tasks concurrently.
pub fn worker_pool_processes_tasks_test() -> Nil {
  let #(db, q) = setup("test_worker_pool")

  // Spawn 5 tasks
  let assert Ok(_) =
    task.spawn(db, q, "ok_task", json.object([]), task.new_options())
  let assert Ok(_) =
    task.spawn(db, q, "ok_task", json.object([]), task.new_options())
  let assert Ok(_) =
    task.spawn(db, q, "ok_task", json.object([]), task.new_options())
  let assert Ok(_) =
    task.spawn(db, q, "ok_task", json.object([]), task.new_options())
  let assert Ok(_) =
    task.spawn(db, q, "ok_task", json.object([]), task.new_options())

  let tracker = process.new_subject()
  let handler = tracking_handler("ok_task", tracker)

  let config =
    worker.new(db, q, [handler])
    |> worker.with_poll_interval(delay_ms(100))
    |> worker.with_batch_size(5)

  // Build a pool of 2 workers in a supervisor
  let pool = worker.pool_child_specs("pool_test", config, 2)

  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(pool_first(pool))
    |> static_supervisor.add(pool_second(pool))
    |> static_supervisor.start()

  // Wait for all 5 tasks to be processed
  let assert Ok(Nil) = process.receive(tracker, 5000)
  let assert Ok(Nil) = process.receive(tracker, 5000)
  let assert Ok(Nil) = process.receive(tracker, 5000)
  let assert Ok(Nil) = process.receive(tracker, 5000)
  let assert Ok(Nil) = process.receive(tracker, 5000)

  let monitor = process.monitor(started.pid)
  process.send_exit(started.pid)
  await_exit(monitor) |> should.equal(Ok(process.Normal))

  let assert Ok(claims) =
    task.claim(db, q, "verify_worker", lease.default_expiry, 10)
  claims |> should.equal([])
  teardown(db, q)
}

fn pool_first(pool: List(a)) -> a {
  let assert Ok(x) = list.first(pool)
  x
}

fn pool_second(pool: List(a)) -> a {
  let assert [_, x, ..] = pool
  x
}

pub fn worker_suspends_and_resumes_a_task_on_event_test() -> Nil {
  let #(db, q) = setup("test_worker_suspend")
  let waits = process.new_subject()
  let handler =
    Handler(
      task_name: "wait",
      execute: fn(ctx) {
        let outcome = context.await_event(ctx, "ready", option.None)
        process.send(waits, outcome)
        case outcome {
          Ok(event.Suspended) -> worker.Suspend
          Ok(event.Received(_)) -> Complete(json.int(context.attempt(ctx)))
          Ok(event.TimedOut) -> Fail(json.string("This wait has no deadline"))
          Error(error) -> Fail(json.string(client.error_message(error)))
        }
      },
      on_error: option.None,
    )
  let assert Ok(info) =
    task.spawn(db, q, "wait", json.null(), task.new_options())
  let assert Ok(started) =
    worker.new(db, q, [handler])
    |> worker.with_poll_interval(delay_ms(20))
    |> worker.start
  process.receive(waits, 2000) |> should.equal(Ok(Ok(event.Suspended)))
  let assert Ok(task.Sleeping(..)) = task.get_result(db, q, info.task_id)

  let assert Ok(Nil) = event.emit(db, q, "ready", json.null())

  process.receive(waits, 2000)
  |> should.equal(Ok(Ok(event.Received("null"))))
  expect_worker_stop(started.data)
  let assert Ok(task.Completed(result: option.Some("1"), ..)) =
    task.get_result(db, q, info.task_id)

  teardown(db, q)
}
