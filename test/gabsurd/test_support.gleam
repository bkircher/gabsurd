//// Shared configuration for database tests.

import envoy

pub fn database_url() -> String {
  let assert Ok(url) = envoy.get("DATABASE_URL")
    as "Set DATABASE_URL before you run the database tests."
  url
}
