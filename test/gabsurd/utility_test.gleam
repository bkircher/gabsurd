//// Tests for utility operations.

import gabsurd/client
import gabsurd/event
import gabsurd/test_support
import gabsurd/utility
import gleam/erlang/process
import gleam/json
import gleam/string
import gleeunit/should

pub fn cleanup_queue_returns_one_result_test() -> Nil {
  use db, name <- test_support.with_transaction_queue("test_cleanup")
  test_support.set_time(db, "2025-01-01T00:00:00Z")
  let assert Ok(Nil) = event.emit(db, name, "done", json.null())
  test_support.set_time(db, "2025-03-01T00:00:00Z")

  let outcome = utility.cleanup_queue(db, name)

  outcome |> should.equal(Ok(utility.CleanupResult("test_cleanup", 0, 1)))
}

pub fn get_schema_version_test() -> Nil {
  let assert Ok(started) = client.start(test_support.database_url())
  let db = started.data

  let assert Ok(version) = utility.get_schema_version(db)
  should.be_true(string.length(version) > 0)

  process.send_exit(db.pid)
}
