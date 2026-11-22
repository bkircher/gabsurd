-- Complete a run only while the original claim is active.
SELECT gabsurd.complete_run_if_claimed($1, $2, $3, $4) AS completed;
