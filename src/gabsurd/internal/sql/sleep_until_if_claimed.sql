-- Interpret the encoded timestamp as UTC, not as session-local time.
SELECT claim_lost, should_suspend
FROM gabsurd.sleep_if_claimed($1, $2, $3, $4, NULL::double precision, $5::timestamp AT TIME ZONE 'UTC', $6);
