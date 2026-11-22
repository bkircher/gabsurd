//// Tests for checkpoint operations.

import gabsurd/checkpoint
import gabsurd/client
import gabsurd/lease
import gabsurd/task
import gabsurd/test_support
import gleam/json
import gleam/list
import gleam/option
import gleeunit/should
import pog
import youid/uuid

pub fn set_checkpoint_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_checkpoint_set")

  let assert Ok(spawned) =
    task.spawn(db, q, "checkpoint_task", json.object([]), task.new_options())
  let assert Ok(claims) =
    task.claim(db, q, "cp-worker", lease.default_expiry, 1)
  let assert Ok(claim) = list.first(claims)

  // Set a checkpoint (extend_claim_by=0 for this test)
  checkpoint.set(
    db,
    q,
    spawned.task_id,
    "step1",
    json.object([#("progress", json.int(50))]),
    claim.run_id,
    0,
  )
  |> should.be_ok
}

pub fn set_checkpoint_rejects_a_run_from_another_task_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_checkpoint_wrong_task")
  let assert Ok(_) =
    task.spawn(db, q, "run_task", json.null(), task.new_options())
  let assert Ok([claim]) = task.claim(db, q, "worker", lease.default_expiry, 1)
  let assert Ok(other) =
    task.spawn(db, q, "other_task", json.null(), task.new_options())

  let outcome =
    checkpoint.set(db, q, other.task_id, "step", json.int(42), claim.run_id, 60)

  let assert Error(client.PostgresqlError(sqlstate: "P0001", ..)) = outcome
  Nil
}

pub fn get_checkpoint_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_checkpoint_get")

  let assert Ok(spawned) =
    task.spawn(db, q, "cp_get_task", json.object([]), task.new_options())
  let assert Ok(claims) =
    task.claim(db, q, "cp-get-worker", lease.default_expiry, 1)
  let assert Ok(claim) = list.first(claims)

  // Set a checkpoint (extend_claim_by=0 for this test)
  let assert Ok(Nil) =
    checkpoint.set(
      db,
      q,
      spawned.task_id,
      "step1",
      json.object([#("progress", json.int(75))]),
      claim.run_id,
      0,
    )

  // Get it back
  let assert Ok(option.Some(cp)) =
    checkpoint.get(db, q, spawned.task_id, "step1", False)
  cp.checkpoint_name |> should.equal("step1")
  cp.state |> should.equal(option.Some("{\"progress\": 75}"))
  cp.status |> should.equal("committed")
  cp.owner_run_id |> should.equal(option.Some(claim.run_id))
}

pub fn checkpoint_retains_sql_null_state_and_owner_test() -> Nil {
  use db, q <- test_support.with_transaction_queue("test_checkpoint_ownerless")
  let assert Ok(spawned) =
    task.spawn(db, q, "workflow", json.null(), task.new_options())
  let task.TaskId(task_uuid) = spawned.task_id
  let assert Ok(_) =
    pog.query(
      "INSERT INTO absurd.c_test_checkpoint_ownerless (task_id, checkpoint_name)
       VALUES ($1, 'step')",
    )
    |> pog.parameter(pog.text(uuid.to_string(task_uuid)))
    |> pog.execute(client.connection(db))

  let outcome = checkpoint.get(db, q, spawned.task_id, "step", False)

  let assert Ok(option.Some(cp)) = outcome
  cp.state |> should.equal(option.None)
  cp.owner_run_id |> should.equal(option.None)
}
