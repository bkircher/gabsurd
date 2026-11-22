//// Converts generated query results to SDK results.

import gabsurd/client.{
  type GabsurdError, ClaimLost, ConnectionError, ConstraintViolated, NotFound,
  PostgresqlError, QueryError, RunAlreadyFailed, TaskCancelled,
  UnexpectedRowCount,
}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import pog

pub fn one(
  returned: Result(pog.Returned(a), pog.QueryError),
) -> Result(a, GabsurdError) {
  case returned {
    Ok(pog.Returned(1, [row])) -> Ok(row)
    Ok(pog.Returned(0, _)) -> Error(NotFound)
    Ok(pog.Returned(count, _)) ->
      Error(UnexpectedRowCount("expected 1 row, got " <> int.to_string(count)))
    Error(error) -> Error(from_pog_error(error))
  }
}

pub fn many(
  returned: Result(pog.Returned(a), pog.QueryError),
) -> Result(List(a), GabsurdError) {
  returned
  |> result.map(fn(rows) { rows.rows })
  |> result.map_error(from_pog_error)
}

pub fn exec(
  returned: Result(pog.Returned(a), pog.QueryError),
) -> Result(Nil, GabsurdError) {
  returned |> result.replace(Nil) |> result.map_error(from_pog_error)
}

pub fn claim_write(
  returned: Result(pog.Returned(a), pog.QueryError),
  written: fn(a) -> Bool,
) -> Result(Nil, GabsurdError) {
  use row <- result.try(one(returned))
  case written(row) {
    True -> Ok(Nil)
    False -> Error(ClaimLost)
  }
}

fn from_pog_error(error: pog.QueryError) -> GabsurdError {
  case error {
    pog.ConstraintViolated(message:, constraint:, detail:) ->
      ConstraintViolated(message:, constraint:, detail:)
    pog.PostgresqlError("AB001", _, _) -> TaskCancelled
    pog.PostgresqlError("AB002", _, message) -> RunAlreadyFailed(message)
    pog.PostgresqlError(code:, name:, message:) ->
      PostgresqlError(sqlstate: code, name:, message:)
    pog.UnexpectedArgumentCount(expected, got) ->
      QueryError(
        "unexpected argument count: expected "
        <> int.to_string(expected)
        <> " got "
        <> int.to_string(got),
      )
    pog.UnexpectedArgumentType(expected, got) ->
      QueryError(
        "unexpected argument type: expected " <> expected <> " got " <> got,
      )
    pog.UnexpectedResultType(errors) ->
      QueryError(
        "decode error: "
        <> string.join(
          list.map(errors, fn(error) {
            error.expected <> " got " <> error.found
          }),
          ", ",
        ),
      )
    pog.QueryTimeout -> QueryError("query timeout")
    pog.ConnectionUnavailable -> ConnectionError("no connection available")
  }
}
