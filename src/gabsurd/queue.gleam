//// Queue management for the Absurd durable workflow system.
//// Provides high-level functions for creating, dropping, and listing queues.

import gabsurd/client.{type Db, type GabsurdError}
import gabsurd/internal/query
import gabsurd/internal/sql
import gleam/list
import gleam/result

/// Storage mode for a queue.
pub type StorageMode {
  Unpartitioned
  Partitioned
}

/// Create a new queue with default (unpartitioned) storage mode.
pub fn create(
  db db: Db,
  queue_name queue_name: String,
) -> Result(Nil, GabsurdError) {
  create_with_mode(db, queue_name, Unpartitioned)
}

/// Create a new queue with a specific storage mode.
pub fn create_with_mode(
  db db: Db,
  queue_name queue_name: String,
  storage_mode storage_mode: StorageMode,
) -> Result(Nil, GabsurdError) {
  let mode = case storage_mode {
    Unpartitioned -> "unpartitioned"
    Partitioned -> "partitioned"
  }
  sql.create_queue_with_mode(client.connection(db), queue_name, mode)
  |> query.exec
}

/// Drop a queue and all its associated tables.
pub fn drop(
  db db: Db,
  queue_name queue_name: String,
) -> Result(Nil, GabsurdError) {
  sql.drop_queue(client.connection(db), queue_name) |> query.exec
}

/// List all queue names.
pub fn list(db: Db) -> Result(List(String), GabsurdError) {
  sql.list_queues(client.connection(db))
  |> query.many
  |> result.map(fn(rows) { list.map(rows, fn(row) { row.queue_name }) })
}
