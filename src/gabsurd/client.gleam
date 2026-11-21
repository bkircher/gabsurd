//// Database client for gabsurd.

import gleam/erlang/process
import gleam/int
import gleam/option
import gleam/otp/actor
import pog

/// A database connection handle.
pub type Db {
  Db(pid: process.Pid, connection: pog.Connection)
}

/// Errors returned by gabsurd operations.
pub type GabsurdError {
  /// The database query failed (connection issue, constraint violation, etc.)
  QueryError(String)
  /// A query returned an unexpected number of rows.
  UnexpectedRowCount(String)
  /// No row was found when one row was expected.
  NotFound
  /// Failed to connect to the database.
  ConnectionError(String)
}

/// Generate a unique integer for pool names.
@external(erlang, "erlang", "unique_integer")
pub fn unique_integer() -> Int

/// Start a database connection from a DATABASE_URL string.
/// Uses a unique pool name to avoid collisions when multiple
/// connections are started (e.g., in tests).
pub fn start(url: String) -> actor.StartResult(Db) {
  let id = unique_integer()
  let name = process.new_name("gabsurd_" <> int.to_string(id))
  let config_result = pog.url_config(name, url)
  case config_result {
    Error(_) -> Error(actor.InitFailed("invalid DATABASE_URL"))
    Ok(config) -> {
      let config = config |> pog.pool_size(2)
      case pog.start(config) {
        Ok(started) ->
          Ok(actor.Started(
            pid: started.pid,
            data: Db(pid: started.pid, connection: started.data),
          ))
        Error(reason) -> Error(reason)
      }
    }
  }
}

/// Start a connection from individual parts (useful for testing).
pub fn start_with(
  host: String,
  port: Int,
  database: String,
  user: String,
  password: String,
) -> actor.StartResult(Db) {
  let id = unique_integer()
  let name = process.new_name("gabsurd_" <> int.to_string(id))
  let config =
    pog.default_config(pool_name: name)
    |> pog.host(host)
    |> pog.port(port)
    |> pog.database(database)
    |> pog.user(user)
    |> pog.password(option.Some(password))
    |> pog.ssl(pog.SslDisabled)
    |> pog.pool_size(2)

  case pog.start(config) {
    Ok(started) ->
      Ok(actor.Started(
        pid: started.pid,
        data: Db(pid: started.pid, connection: started.data),
      ))
    Error(reason) -> Error(reason)
  }
}

/// Get the underlying pog connection.
pub fn connection(db: Db) -> pog.Connection {
  db.connection
}
