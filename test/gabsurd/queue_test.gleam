//// Tests for queue management operations.

import gabsurd/client
import gabsurd/queue
import gabsurd/test_support
import gleam/erlang/process
import gleam/list
import gleeunit/should

pub fn create_queue_test() {
  let assert Ok(started) = client.start(test_support.database_url())
  let db = started.data

  queue.create(db, "test_create") |> should.be_ok

  let assert Ok(queues) = queue.list(db)
  queues |> list.contains("test_create") |> should.be_true

  queue.drop(db, "test_create") |> should.be_ok
  process.send_exit(db.pid)
}

pub fn drop_queue_test() {
  let assert Ok(started) = client.start(test_support.database_url())
  let db = started.data

  let assert Ok(Nil) = queue.create(db, "test_drop")
  queue.drop(db, "test_drop") |> should.be_ok

  let assert Ok(queues) = queue.list(db)
  queues |> list.contains("test_drop") |> should.be_false
  process.send_exit(db.pid)
}

pub fn list_queues_test() {
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

pub fn create_queue_with_mode_test() {
  let assert Ok(started) = client.start(test_support.database_url())
  let db = started.data

  queue.create_with_mode(db, "test_partitioned", "partitioned")
  |> should.be_ok

  let assert Ok(queues) = queue.list(db)
  queues |> list.contains("test_partitioned") |> should.be_true

  let _ = queue.drop(db, "test_partitioned")
  process.send_exit(db.pid)
}
