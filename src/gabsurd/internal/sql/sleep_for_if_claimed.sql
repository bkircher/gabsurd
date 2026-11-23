-- Calculate the deadline on the server only when the checkpoint is new.
SELECT claim_lost, should_suspend
FROM gabsurd.sleep_if_claimed($1, $2, $3, $4, $5, NULL::timestamptz, $6);
