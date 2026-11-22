-- Fail a run only while it is still owned by the same claim.
SELECT gabsurd.fail_run_if_claimed($1, $2, $3, $4) AS failed;
