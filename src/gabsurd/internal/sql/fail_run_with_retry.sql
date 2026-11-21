-- Interpret the encoded timestamp as UTC, not as session-local time.
SELECT absurd.fail_run($1, $2, $3, $4::timestamp AT TIME ZONE 'UTC')::text AS ignored;
