-- An event wait with no deadline.
SELECT should_suspend, payload::text AS "payload?"
FROM gabsurd.await_event($1, $2, $3, $4, $5, NULL::integer);
