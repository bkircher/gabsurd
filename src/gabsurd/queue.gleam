//// Queue management for the Absurd durable workflow system.
//// Provides high-level functions for creating, dropping, and listing queues.

import gabsurd/client.{type Db, type GabsurdError}
import gabsurd/internal/query
import gabsurd/internal/sql
import gleam/list
import gleam/result

/// Create a new queue with default (unpartitioned) storage mode.
pub fn create(db: Db, queue_name: String) -> Result(Nil, GabsurdError) {
  sql.create_queue(client.connection(db), queue_name) |> query.exec
}

/// Create a new queue with a specific storage mode.
pub fn create_with_mode(
  db: Db,
  queue_name: String,
  storage_mode: String,
) -> Result(Nil, GabsurdError) {
  sql.create_queue_with_mode(client.connection(db), queue_name, storage_mode)
  |> query.exec
}

/// Drop a queue and all its associated tables.
pub fn drop(db: Db, queue_name: String) -> Result(Nil, GabsurdError) {
  sql.drop_queue(client.connection(db), queue_name) |> query.exec
}

/// List all queue names.
pub fn list(db: Db) -> Result(List(String), GabsurdError) {
  use rows <- result.try(sql.list_queues(client.connection(db)) |> query.many)
  Ok(rows |> list.map(fn(row) { row.queue_name }))
}
