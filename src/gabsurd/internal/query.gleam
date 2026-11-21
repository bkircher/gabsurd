//// Converts generated query results to SDK results.

import gabsurd/client.{
  type GabsurdError, ConnectionError, NotFound, QueryError, UnexpectedRowCount,
}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import pog
import youid/uuid

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

pub fn uuid_from_bits(bits: BitArray) -> Result(uuid.Uuid, GabsurdError) {
  let error = QueryError("invalid UUID")
  case bits {
    <<_:128>> ->
      uuid.from_bit_array(bits)
      // PostgreSQL also accepts UUIDs without a version, such as the nil UUID.
      |> result.lazy_or(fn() { uuid.from_string(bit_array.base16_encode(bits)) })
      |> result.replace_error(error)
    _ -> Error(error)
  }
}

fn from_pog_error(error: pog.QueryError) -> GabsurdError {
  case error {
    pog.ConstraintViolated(message, _, _) -> QueryError(message)
    pog.PostgresqlError(code, _, message) -> QueryError(code <> ": " <> message)
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
