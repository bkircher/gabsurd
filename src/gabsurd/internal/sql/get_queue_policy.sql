SELECT
  queue_name,
  storage_mode,
  default_partition,
  partition_lookahead::text,
  partition_lookback::text,
  cleanup_ttl::text,
  cleanup_limit,
  detach_mode,
  detach_min_age::text
FROM absurd.get_queue_policy($1);
