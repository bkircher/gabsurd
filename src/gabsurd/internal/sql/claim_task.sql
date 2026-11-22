-- Claim up to the requested number of ready runs.
SELECT
  run_id,
  task_id,
  attempt,
  task_name,
  params,
  retry_strategy AS "retry_strategy?",
  max_attempts AS "max_attempts?",
  headers AS "headers?",
  wake_event AS "wake_event?",
  event_payload AS "event_payload?"
FROM gabsurd.claim_task($1, $2, $3, $4);
