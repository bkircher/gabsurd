//// Cleanup and utility operations for the Absurd durable workflow system.

import gabsurd/client.{type Db, type GabsurdError}
import gabsurd/internal/query
import gabsurd/internal/sql
import gleam/result

/// Result of a cleanup operation for a single queue.
pub type CleanupResult {
  CleanupResult(queue_name: String, tasks_deleted: Int, events_deleted: Int)
}

/// Run one cleanup batch for a named queue and return its deletion counts.
pub fn cleanup_queue(
  db db: Db,
  queue_name queue_name: String,
) -> Result(CleanupResult, GabsurdError) {
  sql.cleanup_all_queues(client.connection(db), queue_name)
  |> query.one
  |> result.map(fn(row) {
    CleanupResult(
      queue_name: row.queue_name,
      tasks_deleted: row.tasks_deleted,
      events_deleted: row.events_deleted,
    )
  })
}

/// Get the schema version from the database.
pub fn get_schema_version(db: Db) -> Result(String, GabsurdError) {
  sql.get_schema_version(client.connection(db))
  |> query.one
  |> result.map(fn(row) { row.get_schema_version })
}
