-- Extend a lease only while the original claim is active.
SELECT gabsurd.extend_claim_if_claimed($1, $2, $3, $4) AS extended;
