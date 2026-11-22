//// Shared configuration for database tests.

import envoy
import gabsurd/client.{type Db}
import gabsurd/queue
import gleam/erlang/process
import pog

pub fn database_url() -> String {
  let assert Ok(url) = envoy.get("DATABASE_URL")
    as "Set DATABASE_URL before you run the database tests."
  url
}

/// Run a single-process database test and roll back its changes.
pub fn with_transaction(check: fn(Db) -> Nil) -> Nil {
  let assert Ok(started) = client.start(database_url())
  let outcome =
    pog.transaction(client.connection(started.data), fn(connection) {
      let db = client.Db(pid: started.pid, connection:)
      check(db)
      Error(Nil)
    })
  process.send_exit(started.pid)
  let assert Error(pog.TransactionRolledBack(Nil)) = outcome
  Nil
}

/// Run a single-process database test with a new unpartitioned queue.
pub fn with_transaction_queue(
  name: String,
  check: fn(Db, String) -> Nil,
) -> Nil {
  use db <- with_transaction
  let assert Ok(Nil) = queue.create(db, name)
  check(db, name)
}

pub fn set_time(db db: Db, at at: String) -> Nil {
  let assert Ok(_) =
    pog.query("SELECT set_config('absurd.fake_now', $1, true)")
    |> pog.parameter(pog.text(at))
    |> pog.execute(client.connection(db))
  Nil
}
