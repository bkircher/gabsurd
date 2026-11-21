SELECT
  checkpoint_name,
  state AS "state?",
  status,
  owner_run_id AS "owner_run_id?",
  updated_at AT TIME ZONE 'UTC' AS updated_at
FROM absurd.get_task_checkpoint_states($1, $2, $3);
