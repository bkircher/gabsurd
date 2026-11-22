-- Local SQL extensions for gabsurd. Keep upstream SQL in vendor/absurd unchanged.
create schema if not exists gabsurd;

-- Exposes task routing metadata alongside Absurd's task result without exposing
-- task params. The dynamic table name is validated and quoted before use.
create or replace function gabsurd.get_task_result (
  p_queue_name text,
  p_task_id uuid
)
  returns table (
    task_id uuid,
    task_name text,
    headers jsonb,
    state text,
    result jsonb,
    failure_reason jsonb
  )
  language plpgsql
as $$
declare
  v_queue_name text := absurd.validate_queue_name(p_queue_name);
begin
  return query execute format(
    'with upstream_result as (
       select * from absurd.get_task_result($1, $2)
     )
     select r.task_id,
            t.task_name,
            t.headers,
            r.state,
            r.result,
            r.failure_reason
       from absurd.%I t
       join upstream_result r on r.task_id = t.task_id
      where t.task_id = $2',
    't_' || v_queue_name
  ) using v_queue_name, p_task_id;
end;
$$;

-- Resolve timed waits in the claim transaction so retries see the result.
create or replace function gabsurd.claim_task (
  p_queue_name text,
  p_worker_id text,
  p_claim_timeout integer,
  p_qty integer
)
  returns table (
    run_id uuid,
    task_id uuid,
    attempt integer,
    task_name text,
    params jsonb,
    retry_strategy jsonb,
    max_attempts integer,
    headers jsonb,
    wake_event text,
    event_payload jsonb
  )
  language plpgsql
as $$
declare
  v_queue_name text := absurd.validate_queue_name(p_queue_name);
  v_claim record;
  v_wake_event text;
  v_event_payload jsonb;
  v_timeout_key text;
begin
  for v_claim in
    select * from absurd.claim_task(v_queue_name, p_worker_id, p_claim_timeout, p_qty)
  loop
    -- An emitter can commit during the claim. Read the current values from
    -- the locked run, not from the snapshot used by the upstream query.
    execute format(
      'select r.wake_event, r.event_payload from absurd.%I r where r.run_id = $1',
      'r_' || v_queue_name
    ) into v_wake_event, v_event_payload using v_claim.run_id;

    if v_wake_event is not null or v_event_payload is not null then
      -- Absurd can delete the wait row before we claim the run. Use the
      -- saved step identity, and remove it on both timeout and delivery.
      execute format(
        'delete from absurd.%I
          where task_id = $1 and owner_run_id = $2
            and checkpoint_name = ''$await-pending:''
          returning case when state->>''event_name'' = $3
                         then state->>''timeout_key'' end',
        'c_' || v_queue_name
      ) into v_timeout_key using v_claim.task_id, v_claim.run_id, v_wake_event;

      if v_wake_event is not null and v_event_payload is null then
        -- Older context waits have no saved step key. Keep their event key.
        perform absurd.set_task_checkpoint_state(
          v_queue_name, v_claim.task_id,
          coalesce(v_timeout_key, '$await-timeout:' || v_wake_event),
          'true'::jsonb, v_claim.run_id, null
        );

        -- A tracked wait now has a lasting outcome. Consume the wake
        -- signal so Absurd does not apply it to a new step for this event.
        -- Leave untracked wakes intact for callers of Absurd's own wait.
        if v_timeout_key is not null then
          execute format(
            'update absurd.%I set wake_event = null where run_id = $1',
            'r_' || v_queue_name
          ) using v_claim.run_id;
        end if;
      end if;
    end if;

    return query select
      v_claim.run_id, v_claim.task_id, v_claim.attempt, v_claim.task_name,
      v_claim.params, v_claim.retry_strategy, v_claim.max_attempts, v_claim.headers,
      v_wake_event, v_event_payload;
  end loop;
end;
$$;

-- Check only the leases that this worker is executing. A failed run can
-- still have a local handler if another worker handled its expiry first.
create or replace function gabsurd.expired_claims (
  p_queue_name text,
  p_run_ids uuid[],
  p_owners text[]
)
  returns table (run_id uuid, claim_owner text)
  language plpgsql
as $$
declare
  v_queue_name text := absurd.validate_queue_name(p_queue_name);
  v_now timestamptz := absurd.current_time();
begin
  -- Skip a lease while a heartbeat or checkpoint holds its lock. Check
  -- the database time again after taking the lock.
  return query execute format(
    'with locked as materialized (
       select r.run_id, r.claimed_by, r.claim_expires_at
         from unnest($1, $2) as tracked(run_id, claim_owner)
         join absurd.%I r on r.run_id = tracked.run_id
                        and r.claimed_by = tracked.claim_owner
        where r.state in (''running'', ''failed'')
          and r.claim_expires_at <= $3
        for update of r skip locked
     )
     select run_id, claimed_by
       from locked
      where claim_expires_at <= absurd.current_time()',
    'r_' || v_queue_name
  ) using p_run_ids, p_owners, v_now;
end;
$$;

-- Hold the run lock through the caller's write. Return the task ID only if
-- the caller owns the active claim.
create or replace function gabsurd.lock_active_claim (
  p_queue_name text,
  p_run_id uuid,
  p_owner text
)
  returns uuid
  language plpgsql
as $$
declare
  v_queue_name text := absurd.validate_queue_name(p_queue_name);
  v_task_id uuid;
  v_task_state text;
  v_run_state text;
  v_owner text;
  v_claim_until timestamptz;
begin
  execute format(
    'select r.task_id, t.state, r.state, r.claimed_by, r.claim_expires_at
       from absurd.%I r
       join absurd.%I t on t.task_id = r.task_id
      where r.run_id = $1
      for update of r',
    'r_' || v_queue_name,
    't_' || v_queue_name
  ) into v_task_id, v_task_state, v_run_state, v_owner, v_claim_until
    using p_run_id;

  if v_run_state = 'cancelled' or v_task_state = 'cancelled' then
    raise exception sqlstate 'AB001' using message = 'Task has been cancelled';
  end if;
  if v_run_state = 'failed' then
    raise exception sqlstate 'AB002'
      using message = format('Run "%s" has already failed in queue "%s"', p_run_id, v_queue_name);
  end if;

  -- Check the time after taking the lock. A NULL expiry has no deadline.
  if v_run_state = 'running' and v_owner = p_owner
     and (v_claim_until is null or v_claim_until > absurd.current_time()) then
    return v_task_id;
  end if;
  return null;
end;
$$;

create or replace function gabsurd.fail_run_if_claimed (
  p_queue_name text,
  p_run_id uuid,
  p_owner text,
  p_reason jsonb
)
  returns boolean
  language plpgsql
as $$
begin
  if gabsurd.lock_active_claim(p_queue_name, p_run_id, p_owner) is null then
    return false;
  end if;
  perform absurd.fail_run(p_queue_name, p_run_id, p_reason);
  return true;
end;
$$;

create or replace function gabsurd.complete_run_if_claimed (
  p_queue_name text,
  p_run_id uuid,
  p_owner text,
  p_state jsonb
)
  returns boolean
  language plpgsql
as $$
begin
  if gabsurd.lock_active_claim(p_queue_name, p_run_id, p_owner) is null then
    return false;
  end if;
  perform absurd.complete_run(p_queue_name, p_run_id, p_state);
  return true;
end;
$$;

create or replace function gabsurd.schedule_run_if_claimed (
  p_queue_name text,
  p_run_id uuid,
  p_owner text,
  p_defer_seconds bigint
)
  returns boolean
  language plpgsql
as $$
begin
  if gabsurd.lock_active_claim(p_queue_name, p_run_id, p_owner) is null then
    return false;
  end if;
  perform absurd.schedule_run(
    p_queue_name, p_run_id,
    absurd.current_time() + make_interval(secs => p_defer_seconds)
  );
  return true;
end;
$$;

-- Check the task and hold the run lock through the checkpoint write.
create or replace function gabsurd.set_task_checkpoint_state (
  p_queue_name text,
  p_task_id uuid,
  p_step_name text,
  p_state jsonb,
  p_owner_run uuid,
  p_extend_claim_by integer
)
  returns void
  language plpgsql
as $$
declare
  v_queue_name text := absurd.validate_queue_name(p_queue_name);
  v_task_id uuid;
begin
  execute format(
    'select task_id from absurd.%I where run_id = $1 and task_id = $2 for update',
    'r_' || v_queue_name
  ) into v_task_id using p_owner_run, p_task_id;

  if v_task_id is null then
    raise exception 'Run "%" not found for task "%" while setting checkpoint', p_owner_run, p_task_id;
  end if;

  perform absurd.set_task_checkpoint_state(
    v_queue_name, v_task_id, p_step_name, p_state, p_owner_run, p_extend_claim_by
  );
end;
$$;

create or replace function gabsurd.set_checkpoint_if_claimed (
  p_queue_name text,
  p_run_id uuid,
  p_owner text,
  p_step_name text,
  p_state jsonb,
  p_extend_by integer
)
  returns boolean
  language plpgsql
as $$
declare
  v_task_id uuid := gabsurd.lock_active_claim(p_queue_name, p_run_id, p_owner);
begin
  if v_task_id is null then
    return false;
  end if;
  perform absurd.set_task_checkpoint_state(
    p_queue_name, v_task_id, p_step_name, p_state, p_run_id, p_extend_by
  );
  return true;
end;
$$;

create or replace function gabsurd.extend_claim_if_claimed (
  p_queue_name text,
  p_run_id uuid,
  p_owner text,
  p_extend_by integer
)
  returns boolean
  language plpgsql
as $$
begin
  if gabsurd.lock_active_claim(p_queue_name, p_run_id, p_owner) is null then
    return false;
  end if;
  -- A claim without a deadline only needs the ownership check.
  if p_extend_by = 0 then
    return true;
  end if;
  perform absurd.extend_claim(p_queue_name, p_run_id, p_extend_by);
  return true;
end;
$$;

-- Use the same saved outcomes for waits with and without a claim check.
create or replace function gabsurd.await_event (
  p_queue_name text,
  p_task_id uuid,
  p_run_id uuid,
  p_step_name text,
  p_event_name text,
  p_timeout integer,
  p_owner text default null
)
  returns table (
    claim_lost boolean,
    should_suspend boolean,
    payload jsonb
  )
  language plpgsql
as $$
declare
  v_queue_name text := absurd.validate_queue_name(p_queue_name);
  -- Keep the existing keys for context waits. Raw waits use the explicit
  -- step name so different steps can wait for the same event.
  v_timeout_key text := case
    when p_step_name = '$await:' || p_event_name then '$await-timeout:' || p_event_name
    else '$await-step-timeout:' || p_step_name
  end;
  v_task_id uuid;
  v_timed_out boolean;
  v_checkpoint_payload jsonb;
  v_event_locked boolean;
  v_event_inserted boolean;
  v_await record;
begin
  if p_event_name is null or length(trim(p_event_name)) = 0 then
    raise exception 'event_name must be provided';
  end if;
  if p_timeout < 0 then
    raise exception 'timeout must be non-negative';
  end if;

  -- A saved outcome needs no write or event lock. A timeout takes
  -- precedence over any later payload.
  execute format(
    'select r.task_id, timeout_cp.state = ''true''::jsonb, payload_cp.state
       from absurd.%1$I r
       left join absurd.%2$I timeout_cp
         on timeout_cp.task_id = r.task_id and timeout_cp.checkpoint_name = $2
        and timeout_cp.status = ''committed''
       left join absurd.%2$I payload_cp
         on payload_cp.task_id = r.task_id and payload_cp.checkpoint_name = $3
      where r.run_id = $1',
    'r_' || v_queue_name, 'c_' || v_queue_name
  ) into v_task_id, v_timed_out, v_checkpoint_payload
    using p_run_id, v_timeout_key, p_step_name;

  if p_task_id is not null and v_task_id is distinct from p_task_id then
    raise exception 'Run "%" not found for task "%" while awaiting event', p_run_id, p_task_id;
  end if;

  if v_timed_out or v_checkpoint_payload is not null then
    return query select false, false,
      case when v_timed_out then null::jsonb else v_checkpoint_payload end;
    return;
  end if;

  if p_owner is not null then
    -- Lock the event before the run, as emit_event does. If the event does
    -- not exist, insert a placeholder that this transaction owns. Repeat if
    -- another transaction inserted or removed the row in the meantime.
    loop
      execute format(
        'select true from absurd.%I where event_name = $1 for share',
        'e_' || v_queue_name
      ) into v_event_locked using p_event_name;
      exit when v_event_locked;

      execute format(
        'insert into absurd.%I (event_name, payload, emitted_at)
         values ($1, null, ''epoch''::timestamptz)
         on conflict (event_name) do nothing
         returning true',
        'e_' || v_queue_name
      ) into v_event_inserted using p_event_name;
      exit when v_event_inserted;
    end loop;

    v_task_id := gabsurd.lock_active_claim(v_queue_name, p_run_id, p_owner);
    if v_task_id is null then
      -- Do not leave a placeholder for a rejected wait.
      if v_event_inserted then
        execute format(
          'delete from absurd.%I where event_name = $1',
          'e_' || v_queue_name
        ) using p_event_name;
      end if;
      return query select true, false, null::jsonb;
      return;
    end if;
  end if;

  select a.* into strict v_await
    from absurd.await_event(
      v_queue_name, v_task_id, p_run_id, p_step_name, p_event_name, p_timeout
    ) a;

  if v_await.should_suspend and p_timeout is not null then
    -- Record which step is waiting while Absurd still holds the run lock.
    perform absurd.set_task_checkpoint_state(
      v_queue_name, v_task_id, '$await-pending:',
      jsonb_build_object('event_name', p_event_name, 'timeout_key', v_timeout_key),
      p_run_id, null
    );
  end if;

  return query select false, v_await.should_suspend, v_await.payload;
end;
$$;
