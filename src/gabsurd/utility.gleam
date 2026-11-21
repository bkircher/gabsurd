//// Cleanup and utility operations for the Absurd durable workflow system.

import gabsurd/client.{type Db, type GabsurdError}
import gabsurd/internal/query
import gabsurd/internal/sql
import gleam/list
import gleam/result

/// Result of a cleanup operation for a single queue.
pub type CleanupResult {
  CleanupResult(queue_name: String, tasks_deleted: Int, events_deleted: Int)
}

/// Run cleanup for a specific queue (deletes old completed/failed tasks and processed events).
pub fn cleanup_queue(
  db: Db,
  queue_name: String,
) -> Result(List(CleanupResult), GabsurdError) {
  use rows <- result.try(
    sql.cleanup_all_queues(client.connection(db), queue_name) |> query.many,
  )
  Ok(
    list.map(rows, fn(row) {
      CleanupResult(
        queue_name: row.queue_name,
        tasks_deleted: row.tasks_deleted,
        events_deleted: row.events_deleted,
      )
    }),
  )
}

/// Get the schema version from the database.
pub fn get_schema_version(db: Db) -> Result(String, GabsurdError) {
  use row <- result.try(
    sql.get_schema_version(client.connection(db)) |> query.one,
  )
  Ok(row.get_schema_version)
}
