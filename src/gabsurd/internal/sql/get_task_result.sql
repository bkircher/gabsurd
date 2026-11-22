SELECT
  task_id,
  task_name,
  headers AS "headers?",
  state,
  result AS "result?",
  failure_reason AS "failure_reason?"
FROM gabsurd.get_task_result($1, $2);
