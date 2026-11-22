-- Schedule a run only while the original claim is active.
SELECT gabsurd.schedule_run_if_claimed($1, $2, $3, $4) AS scheduled;
