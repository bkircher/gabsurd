SELECT queue_name, tasks_deleted, events_deleted
FROM absurd.cleanup_all_queues($1);
