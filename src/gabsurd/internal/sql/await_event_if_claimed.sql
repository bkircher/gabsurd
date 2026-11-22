-- A timed event wait that checks the claim before a write.
SELECT claim_lost, should_suspend, payload::text AS "payload?"
FROM gabsurd.await_event($1, NULL::uuid, $2, $4, $5, $6, $3);
