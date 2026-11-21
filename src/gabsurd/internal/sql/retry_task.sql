SELECT task_id, run_id, attempt, created
FROM absurd.retry_task($1, $2, $3);
