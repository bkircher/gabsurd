-- Interpret the encoded timestamp as UTC, not as session-local time.
SELECT absurd.schedule_run($1, $2, $3::timestamp AT TIME ZONE 'UTC')::text AS ignored;
