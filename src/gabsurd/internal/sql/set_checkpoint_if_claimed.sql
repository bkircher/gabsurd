-- Save a checkpoint only while the original claim is active.
SELECT gabsurd.set_checkpoint_if_claimed($1, $2, $3, $4, $5, $6) AS saved;
