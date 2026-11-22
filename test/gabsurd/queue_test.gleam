//// Tests for queue management operations.

import gabsurd/client
import gabsurd/queue
import gabsurd/test_support
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import gleeunit/should
import pog

pub fn create_queue_test() -> Nil {
  let assert Ok(started) = client.start(test_support.database_url())
  let db = started.data

  queue.create(db, "test_create") |> should.be_ok

  let assert Ok(queues) = queue.list(db)
  queues |> list.contains("test_create") |> should.be_true

  queue.drop(db, "test_create") |> should.be_ok
  process.send_exit(db.pid)
}

pub fn drop_queue_test() -> Nil {
  let assert Ok(started) = client.start(test_support.database_url())
  let db = started.data

  let assert Ok(Nil) = queue.create(db, "test_drop")
  queue.drop(db, "test_drop") |> should.be_ok

  let assert Ok(queues) = queue.list(db)
  queues |> list.contains("test_drop") |> should.be_false
  process.send_exit(db.pid)
}

pub fn list_queues_test() -> Nil {
  let assert Ok(started) = client.start(test_support.database_url())
  let db = started.data

  let assert Ok(Nil) = queue.create(db, "test_list_a")
  let assert Ok(Nil) = queue.create(db, "test_list_b")

  let assert Ok(queues) = queue.list(db)
  queues |> list.contains("test_list_a") |> should.be_true
  queues |> list.contains("test_list_b") |> should.be_true

  let _ = queue.drop(db, "test_list_a")
  let _ = queue.drop(db, "test_list_b")
  process.send_exit(db.pid)
}

pub fn create_partitioned_queue_test() -> Nil {
  use db <- test_support.with_transaction
  let name = "test_partitioned"

  let outcome = queue.create_with_mode(db, name, queue.Partitioned)

  outcome |> should.equal(Ok(Nil))
  storage_mode(db, name) |> should.equal("partitioned")
}

pub fn create_unpartitioned_queue_with_mode_test() -> Nil {
  use db <- test_support.with_transaction
  let name = "test_unpartitioned"

  let outcome = queue.create_with_mode(db, name, queue.Unpartitioned)

  outcome |> should.equal(Ok(Nil))
  storage_mode(db, name) |> should.equal("unpartitioned")
}

fn storage_mode(db: client.Db, name: String) -> String {
  let assert Ok(pog.Returned(1, [mode])) =
    pog.query("SELECT storage_mode FROM absurd.get_queue_policy($1)")
    |> pog.parameter(pog.text(name))
    |> pog.returning(decode.field(0, decode.string, decode.success))
    |> pog.execute(client.connection(db))
  mode
}
