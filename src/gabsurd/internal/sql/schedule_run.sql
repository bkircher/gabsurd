-- Schedule a run relative to the database clock.
SELECT absurd.schedule_run($1, $2, absurd.current_time() + make_interval(secs => $3::bigint))::text AS ignored;
