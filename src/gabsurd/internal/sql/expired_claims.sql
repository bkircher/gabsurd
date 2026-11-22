-- Find the worker's expired leases without claiming any new work.
SELECT run_id, claim_owner
FROM gabsurd.expired_claims($1, $2, $3);
