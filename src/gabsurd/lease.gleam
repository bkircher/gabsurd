//// Claim expiry settings for workers and callers that claim tasks directly.

import gleam/bool

/// A positive number of seconds that fits in a PostgreSQL integer.
pub opaque type LeaseSeconds {
  LeaseSeconds(Int)
}

/// Choose a lease duration or claim without a deadline.
pub type ClaimExpiry {
  ExpiresAfter(LeaseSeconds)
  /// The claim has no deadline. It cannot be recovered through lease expiry.
  NoExpiry
}

/// The lease duration is outside the range of a positive PostgreSQL integer.
pub type LeaseError {
  LeaseSecondsOutOfRange
}

const max_lease_seconds = 2_147_483_647

/// The default lease expires after 30 seconds.
pub const default_expiry = ExpiresAfter(LeaseSeconds(30))

/// Check that a lease duration is between 1 and 2,147,483,647 seconds.
pub fn seconds(seconds: Int) -> Result(LeaseSeconds, LeaseError) {
  use <- bool.guard(
    when: seconds < 1 || seconds > max_lease_seconds,
    return: Error(LeaseSecondsOutOfRange),
  )
  Ok(LeaseSeconds(seconds))
}

/// Read the number of seconds in a checked lease duration.
pub fn to_seconds(duration: LeaseSeconds) -> Int {
  let LeaseSeconds(seconds) = duration
  seconds
}

// Absurd uses zero to claim without a deadline or skip a lease extension.
@internal
pub fn to_sql_seconds(expiry: ClaimExpiry) -> Int {
  case expiry {
    ExpiresAfter(duration) -> to_seconds(duration)
    NoExpiry -> 0
  }
}
