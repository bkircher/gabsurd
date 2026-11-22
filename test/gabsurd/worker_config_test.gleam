import gabsurd/worker
import gleeunit/should

pub fn delay_accepts_both_limits_test() -> Nil {
  let minimum = worker.delay_ms(1)
  let maximum = worker.delay_ms(4_294_967_295)

  let assert Ok(_) = minimum
  let assert Ok(_) = maximum
  Nil
}

pub fn delay_rejects_non_positive_values_test() -> Nil {
  let negative = worker.delay_ms(-1)
  let zero = worker.delay_ms(0)

  negative |> should.equal(Error(worker.DelayOutOfRange))
  zero |> should.equal(Error(worker.DelayOutOfRange))
}

pub fn delay_rejects_values_above_the_limit_test() -> Nil {
  let outcome = worker.delay_ms(4_294_967_296)

  outcome |> should.equal(Error(worker.DelayOutOfRange))
}
