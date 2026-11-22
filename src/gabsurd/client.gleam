//// Database client for gabsurd.

import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/option
import gleam/otp/actor
import gleam/result
import pog

/// A database connection handle.
pub type Db {
  Db(pid: process.Pid, connection: pog.Connection)
}

/// Errors returned by gabsurd operations.
pub type GabsurdError {
  /// The driver or SDK could not run the query or read its result.
  QueryError(String)
  /// A PostgreSQL error. The name is "unknown" if Pog does not know the SQLSTATE.
  PostgresqlError(sqlstate: String, name: String, message: String)
  /// A database constraint violation. Pog does not supply its SQLSTATE.
  ConstraintViolated(message: String, constraint: String, detail: String)
  /// The task was cancelled (SQLSTATE AB001).
  TaskCancelled
  /// The handler no longer owns an active claim on the run.
  ClaimLost
  /// This run has already failed (SQLSTATE AB002).
  RunAlreadyFailed(String)
  /// The step result does not match the supplied decoder.
  CheckpointDecodeError(json.DecodeError)
  /// A query returned an unexpected number of rows.
  UnexpectedRowCount(String)
  /// No row was found when one row was expected.
  NotFound
  /// Failed to connect to the database.
  ConnectionError(String)
}

/// Describe an SDK error for logs or diagnostics.
pub fn error_message(error: GabsurdError) -> String {
  case error {
    QueryError(message) | ConstraintViolated(message:, ..) ->
      "query error: " <> message
    PostgresqlError(sqlstate:, message:, ..) ->
      "query error: " <> sqlstate <> ": " <> message
    TaskCancelled -> "task cancelled"
    ClaimLost -> "claim lost"
    RunAlreadyFailed(message) -> message
    CheckpointDecodeError(_) -> "could not decode the step result"
    UnexpectedRowCount(message) -> message
    NotFound -> "not found"
    ConnectionError(message) -> "connection error: " <> message
  }
}

/// Generate a unique integer for pool names.
@external(erlang, "erlang", "unique_integer")
pub fn unique_integer() -> Int

/// Start a database connection from a DATABASE_URL string.
/// Uses a unique pool name to avoid collisions when multiple
/// connections are started (e.g., in tests).
pub fn start(url: String) -> actor.StartResult(Db) {
  pog.url_config(new_pool_name(), url)
  |> result.replace_error(actor.InitFailed("invalid DATABASE_URL"))
  |> result.try(start_pool)
}

// nolint: unused_exports -- public API for callers with separate connection settings
/// Start a connection from individual parts (useful for testing).
pub fn start_with(
  host host: String,
  port port: Int,
  database database: String,
  user user: String,
  password password: String,
) -> actor.StartResult(Db) {
  pog.default_config(pool_name: new_pool_name())
  |> pog.host(host)
  |> pog.port(port)
  |> pog.database(database)
  |> pog.user(user)
  |> pog.password(option.Some(password))
  |> pog.ssl(pog.SslDisabled)
  |> start_pool
}

fn new_pool_name() -> process.Name(pog.Message) {
  let id = unique_integer()
  process.new_name("gabsurd_" <> int.to_string(id))
}

fn start_pool(config: pog.Config) -> actor.StartResult(Db) {
  config
  |> pog.pool_size(2)
  |> pog.start
  |> result.map(fn(started) {
    let actor.Started(pid, connection) = started
    actor.Started(pid:, data: Db(pid:, connection:))
  })
}

/// Get the underlying pog connection.
pub fn connection(db: Db) -> pog.Connection {
  db.connection
}
