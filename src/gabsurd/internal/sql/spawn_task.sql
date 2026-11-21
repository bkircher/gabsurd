SELECT task_id, run_id, attempt, created
FROM absurd.spawn_task($1, $2, $3, $4);
