import gabsurd/lease
import gleam/result
import gleeunit/should

pub fn lease_accepts_both_limits_test() -> Nil {
  let minimum = lease.seconds(1)
  let maximum = lease.seconds(2_147_483_647)

  minimum |> result.map(lease.to_seconds) |> should.equal(Ok(1))
  maximum |> result.map(lease.to_seconds) |> should.equal(Ok(2_147_483_647))
}

pub fn lease_rejects_non_positive_values_test() -> Nil {
  let negative = lease.seconds(-1)
  let zero = lease.seconds(0)

  negative |> should.equal(Error(lease.LeaseSecondsOutOfRange))
  zero |> should.equal(Error(lease.LeaseSecondsOutOfRange))
}

pub fn lease_rejects_values_above_the_postgresql_limit_test() -> Nil {
  let outcome = lease.seconds(2_147_483_648)

  outcome |> should.equal(Error(lease.LeaseSecondsOutOfRange))
}
