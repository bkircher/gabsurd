-- A timed wait. Keep SQL NULL distinct from the JSON value null.
SELECT should_suspend, payload::text AS "payload?"
FROM absurd.await_event($1, $2, $3, $4, $5, $6);
