//// Task lifecycle operations for the Absurd durable workflow system.
//// Provides high-level functions for spawning, claiming, completing,
//// failing, and cancelling tasks.

import gabsurd/client.{type Db, type GabsurdError}
import gabsurd/internal/query
import gabsurd/internal/sql
import gabsurd/lease.{type ClaimExpiry}
import gleam/function
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/time/timestamp
import youid/uuid

// ============================================================================
// Public Types
// ============================================================================

/// The UUID of a task. It stays the same across retries.
pub type TaskId {
  TaskId(uuid.Uuid)
}

/// The UUID of one attempt to run a task.
pub type RunId {
  RunId(uuid.Uuid)
}

/// Information returned when spawning a task.
pub type SpawnInfo {
  SpawnInfo(task_id: TaskId, run_id: RunId, attempt: Int, created: Bool)
}

/// Information returned when claiming a task. SQL NULL is `None`.
pub type Claim {
  Claim(
    run_id: RunId,
    task_id: TaskId,
    attempt: Int,
    task_name: String,
    params: String,
    retry_strategy: option.Option(String),
    /// `None` means this task has no attempt limit.
    max_attempts: option.Option(Int),
    headers: option.Option(String),
    wake_event: option.Option(String),
    event_payload: option.Option(String),
  )
}

/// Current state and routing metadata for a task.
/// Optional JSON fields contain JSON text. SQL NULL is `None`, not `Some("null")`.
pub type TaskResult {
  Pending(task_name: String, headers: option.Option(String))
  Running(task_name: String, headers: option.Option(String))
  Sleeping(task_name: String, headers: option.Option(String))
  Completed(
    task_name: String,
    headers: option.Option(String),
    result: option.Option(String),
  )
  Failed(
    task_name: String,
    headers: option.Option(String),
    failure_reason: option.Option(String),
  )
  Cancelled(task_name: String, headers: option.Option(String))
}

/// Options for spawning a task.
///
/// Create with `new_options()` and customize with `with_*` functions.
///
/// ## Example
///
/// ```gleam
/// let opts =
///   task.new_options()
///   |> task.with_max_attempts(3)
///   |> task.with_retry_strategy(task.FixedRetry(base_seconds: 30))
///   |> task.with_idempotency_key("order-123")
/// ```
pub type SpawnOptions {
  SpawnOptions(
    max_attempts: AttemptLimit,
    retry_strategy: option.Option(RetryStrategy),
    cancellation: option.Option(Cancellation),
    headers: option.Option(json.Json),
    idempotency_key: option.Option(String),
  )
}

/// Maximum total attempts for a new task, including its first attempt.
pub type AttemptLimit {
  /// Five attempts for a new task.
  DefaultAttempts
  LimitedAttempts(Int)
  UnlimitedAttempts
}

const default_max_attempts = 5

/// Retry strategy for failed tasks.
pub type RetryStrategy {
  /// Retry with a fixed delay between attempts.
  FixedRetry(base_seconds: Int)
  /// Retry with exponential backoff.
  /// `base_seconds` is the initial delay, `factor` is the multiplier,
  /// `max_seconds` caps the delay.
  ExponentialRetry(
    base_seconds: Int,
    factor: Float,
    max_seconds: option.Option(Float),
  )
}

/// Cancellation policy for a task.
pub type Cancellation {
  /// Cancel the task if it runs longer than `max_duration` seconds.
  Cancellation(max_duration: Int)
}

/// Options for retrying a failed task in place.
pub type RetryOptions {
  RetryOptions(
    /// A new total attempt limit. It must exceed the number of attempts already
    /// made. With `None`, the database adds one to the previous limit, or to
    /// the number of attempts already made if the task had no limit.
    max_attempts: option.Option(Int),
  )
}

// ============================================================================
// Options Builders
// ============================================================================

/// Create spawn options with a limit of five total attempts.
pub fn new_options() -> SpawnOptions {
  SpawnOptions(
    max_attempts: DefaultAttempts,
    retry_strategy: option.None,
    cancellation: option.None,
    headers: option.None,
    idempotency_key: option.None,
  )
}

/// Set the maximum total attempts for this task, including the first attempt.
pub fn with_max_attempts(
  options options: SpawnOptions,
  max max: Int,
) -> SpawnOptions {
  SpawnOptions(..options, max_attempts: LimitedAttempts(max))
}

/// Spawn a task without an attempt limit.
pub fn with_unlimited_attempts(options: SpawnOptions) -> SpawnOptions {
  SpawnOptions(..options, max_attempts: UnlimitedAttempts)
}

// nolint: unused_exports -- public API for callers that set a retry policy
/// Set the retry strategy for failed tasks.
pub fn with_retry_strategy(
  options options: SpawnOptions,
  strategy strategy: RetryStrategy,
) -> SpawnOptions {
  SpawnOptions(..options, retry_strategy: option.Some(strategy))
}

// nolint: unused_exports -- public API for callers that set a cancellation policy
/// Set the cancellation policy.
pub fn with_cancellation(
  options options: SpawnOptions,
  cancellation cancellation: Cancellation,
) -> SpawnOptions {
  SpawnOptions(..options, cancellation: option.Some(cancellation))
}

/// Set headers (arbitrary JSON metadata).
pub fn with_headers(
  options options: SpawnOptions,
  headers headers: json.Json,
) -> SpawnOptions {
  SpawnOptions(..options, headers: option.Some(headers))
}

/// Set an idempotency key to prevent duplicate task creation.
pub fn with_idempotency_key(
  options options: SpawnOptions,
  key key: String,
) -> SpawnOptions {
  SpawnOptions(..options, idempotency_key: option.Some(key))
}

/// Create retry options that add one attempt to the task's limit.
pub fn new_retry_options() -> RetryOptions {
  RetryOptions(max_attempts: option.None)
}

/// Encode spawn options to a JSON string for the database.
pub fn encode_options(options: SpawnOptions) -> String {
  options_json(options) |> json.to_string
}

fn options_json(options: SpawnOptions) -> json.Json {
  let max_attempts = case options.max_attempts {
    DefaultAttempts -> option.Some(default_max_attempts)
    LimitedAttempts(max) -> option.Some(max)
    UnlimitedAttempts -> option.None
  }
  attempt_entries(max_attempts)
  |> optional_field(
    "retry_strategy",
    options.retry_strategy,
    encode_retry_strategy,
  )
  |> optional_field("cancellation", options.cancellation, encode_cancellation)
  |> optional_field("headers", options.headers, function.identity)
  |> optional_field("idempotency_key", options.idempotency_key, json.string)
  |> json.object
}

fn attempt_entries(limit: option.Option(Int)) -> List(#(String, json.Json)) {
  optional_field([], "max_attempts", limit, json.int)
}

fn optional_field(
  entries: List(#(String, json.Json)),
  key: String,
  value: option.Option(a),
  encode: fn(a) -> json.Json,
) -> List(#(String, json.Json)) {
  case value {
    option.Some(value) -> [#(key, encode(value)), ..entries]
    option.None -> entries
  }
}

fn encode_retry_strategy(strategy: RetryStrategy) -> json.Json {
  case strategy {
    FixedRetry(base_seconds) ->
      json.object([
        #("kind", json.string("fixed")),
        #("base_seconds", json.int(base_seconds)),
      ])
    ExponentialRetry(base_seconds, factor, max_seconds) ->
      [
        #("kind", json.string("exponential")),
        #("base_seconds", json.int(base_seconds)),
        #("factor", json.float(factor)),
      ]
      |> optional_field("max_seconds", max_seconds, json.float)
      |> json.object
  }
}

fn encode_cancellation(c: Cancellation) -> json.Json {
  let Cancellation(max_duration) = c
  json.object([#("max_duration", json.int(max_duration))])
}

// ============================================================================
// Task Operations
// ============================================================================

/// Spawn a new task in a queue with typed options.
///
/// `params` is a `json.Json` value — use `json.object`, `json.string`, etc.
/// to build it. `options` is a `SpawnOptions` record — use `new_options()` and
/// `with_*` builders.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(info) = task.spawn(
///   db,
///   "emails",
///   "send_welcome",
///   json.object([#("to", json.string("user@example.com"))]),
///   task.new_options() |> task.with_max_attempts(3),
/// )
/// ```
pub fn spawn(
  db db: Db,
  queue_name queue_name: String,
  task_name task_name: String,
  params params: json.Json,
  options options: SpawnOptions,
) -> Result(SpawnInfo, GabsurdError) {
  sql.spawn_task(
    client.connection(db),
    queue_name,
    task_name,
    params,
    options_json(options),
  )
  |> query.one
  |> result.map(fn(row) {
    SpawnInfo(
      task_id: TaskId(row.task_id),
      run_id: RunId(row.run_id),
      attempt: row.attempt,
      created: row.created,
    )
  })
}

/// Claim available tasks from a queue for a worker.
pub fn claim(
  db db: Db,
  queue_name queue_name: String,
  worker_id worker_id: String,
  claim_expiry claim_expiry: ClaimExpiry,
  qty qty: Int,
) -> Result(List(Claim), GabsurdError) {
  sql.claim_task(
    client.connection(db),
    queue_name,
    worker_id,
    lease.to_sql_seconds(claim_expiry),
    qty,
  )
  |> query.many
  |> result.map(fn(rows) {
    list.map(rows, fn(row) {
      Claim(
        run_id: RunId(row.run_id),
        task_id: TaskId(row.task_id),
        attempt: row.attempt,
        task_name: row.task_name,
        params: row.params,
        retry_strategy: row.retry_strategy,
        max_attempts: row.max_attempts,
        headers: row.headers,
        wake_event: row.wake_event,
        event_payload: row.event_payload,
      )
    })
  })
}

/// Mark a run as completed with a JSON result.
pub fn complete(
  db db: Db,
  queue_name queue_name: String,
  run_id run_id: RunId,
  state state: json.Json,
) -> Result(Nil, GabsurdError) {
  let RunId(run_uuid) = run_id
  sql.complete_run(client.connection(db), queue_name, run_uuid, state)
  |> query.exec
}

/// Mark a run as failed with a reason.
/// Passes NULL for retry_at so the queue's retry policy controls retries.
pub fn fail(
  db db: Db,
  queue_name queue_name: String,
  run_id run_id: RunId,
  reason reason: json.Json,
) -> Result(Nil, GabsurdError) {
  let RunId(run_uuid) = run_id
  sql.fail_run(client.connection(db), queue_name, run_uuid, reason)
  |> query.exec
}

// nolint: unused_exports -- public API for callers that schedule a retry
/// Mark a run as failed and schedule a retry at a specific time.
pub fn fail_with_retry(
  db db: Db,
  queue_name queue_name: String,
  run_id run_id: RunId,
  reason reason: json.Json,
  retry_at retry_at: timestamp.Timestamp,
) -> Result(Nil, GabsurdError) {
  let RunId(run_uuid) = run_id
  sql.fail_run_with_retry(
    client.connection(db),
    queue_name,
    run_uuid,
    reason,
    retry_at,
  )
  |> query.exec
}

// nolint: unused_exports -- public API for callers that manage their own claims
/// Extend a worker's claim lease on a run by `extend_by` seconds.
///
/// This function does not check the claim owner or expiry. In a worker
/// handler, use `context.heartbeat` instead.
pub fn extend_claim(
  db db: Db,
  queue_name queue_name: String,
  run_id run_id: RunId,
  extend_by extend_by: Int,
) -> Result(Nil, GabsurdError) {
  let RunId(run_uuid) = run_id
  sql.extend_claim(client.connection(db), queue_name, run_uuid, extend_by)
  |> query.exec
}

/// Schedule a run to become available again in `defer_seconds` seconds,
/// measured by the database clock.
///
/// This function does not check the claim owner or expiry.
pub fn schedule_run(
  db db: Db,
  queue_name queue_name: String,
  run_id run_id: RunId,
  defer_seconds defer_seconds: Int,
) -> Result(Nil, GabsurdError) {
  let RunId(run_uuid) = run_id
  sql.schedule_run(client.connection(db), queue_name, run_uuid, defer_seconds)
  |> query.exec
}

/// Cancel a task by its task_id.
pub fn cancel(
  db db: Db,
  queue_name queue_name: String,
  task_id task_id: TaskId,
) -> Result(Nil, GabsurdError) {
  let TaskId(task_uuid) = task_id
  sql.cancel_task(client.connection(db), queue_name, task_uuid) |> query.exec
}

/// Get the current state and routing metadata of a task.
/// Only `Completed` can contain a result, and only `Failed` can contain a reason.
pub fn get_result(
  db db: Db,
  queue_name queue_name: String,
  task_id task_id: TaskId,
) -> Result(TaskResult, GabsurdError) {
  let TaskId(task_uuid) = task_id
  use row <- result.try(
    sql.get_task_result(client.connection(db), queue_name, task_uuid)
    |> query.one,
  )
  let task_name = row.task_name
  let headers = row.headers
  case row.state {
    "pending" -> Ok(Pending(task_name:, headers:))
    "running" -> Ok(Running(task_name:, headers:))
    "sleeping" -> Ok(Sleeping(task_name:, headers:))
    "completed" -> Ok(Completed(task_name:, headers:, result: row.result))
    "failed" ->
      Ok(Failed(task_name:, headers:, failure_reason: row.failure_reason))
    "cancelled" -> Ok(Cancelled(task_name:, headers:))
    state -> Error(client.QueryError("unknown task state: " <> state))
  }
}

/// Retry a failed task in place. Use `new_retry_options()` to add one attempt
/// or set a new total limit with `RetryOptions(max_attempts: option.Some(n))`.
pub fn retry(
  db db: Db,
  queue_name queue_name: String,
  task_id task_id: TaskId,
  options options: RetryOptions,
) -> Result(SpawnInfo, GabsurdError) {
  let TaskId(task_uuid) = task_id
  let payload = json.object(attempt_entries(options.max_attempts))
  sql.retry_task(client.connection(db), queue_name, task_uuid, payload)
  |> query.one
  |> result.map(fn(row) {
    SpawnInfo(
      task_id: TaskId(row.task_id),
      run_id: RunId(row.run_id),
      attempt: row.attempt,
      created: row.created,
    )
  })
}
