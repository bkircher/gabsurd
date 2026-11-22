# gabsurd

A Gleam SDK for the [Absurd](https://github.com/absurd-sql/absurd) durable workflow system. It uses Squirrel to generate type-safe database queries and OTP worker actors to process tasks.

## Overview

**gabsurd** wraps the Absurd PostgreSQL schema with two layers:

1. **Internal SQL layer** (`gabsurd/internal/sql`) — [Squirrel](https://github.com/giacomocavalieri/squirrel) generates query functions that run through Pog. The queries call Absurd's PostgreSQL functions or the local extension in `priv/gabsurd.sql`.
2. **SDK layer** — Hand-written Gleam modules providing ergonomic APIs for queues, tasks, events, checkpoints, and worker actors.

## Quick Start

### 1. Install and Set Up

```toml
# gleam.toml
[dependencies]
gabsurd = { path = "..." }
gleam_erlang = ">= 1.3.0 and < 2.0.0"
gleam_otp = ">= 1.2.0 and < 2.0.0"
gleam_time = ">= 1.8.0 and < 2.0.0"
```

For local development, use [Docker Compose](#development). Otherwise,
load the vendored Absurd schema first, then install gabsurd's own little SQL extension:

```bash
export DATABASE_URL="postgresql://user:pass@localhost:5432/mydb"
psql "$DATABASE_URL" -f vendor/absurd/sql/absurd.sql
psql "$DATABASE_URL" -f priv/gabsurd.sql
```

`priv/gabsurd.sql` depends on the Absurd schema and must be applied after it.
Apply it again to an existing database before you start workers with this update.

### 2. Connect to the Database

```gleam
import gabsurd/client

let assert Ok(started) = client.start("postgresql://user:pass@localhost:5432/mydb")
let db = started.data
```

### 3. Create a Queue

```gleam
import gabsurd/queue

let assert Ok(Nil) = queue.create(db, "emails")
```

### 4. Spawn Tasks

```gleam
import gleam/json
import gabsurd/task

let assert Ok(info) =
  task.spawn(
    db,
    "emails",
    "send_welcome",
    json.object([#("to", json.string("user@example.com"))]),
    task.new_options() |> task.with_max_attempts(3),
  )
```

### 5. Start a Worker

```gleam
import gabsurd/lease
import gabsurd/worker.{Complete, Handler}
import gleam/json
import gleam/option

let email_handler = Handler(
  task_name: "send_welcome",
  execute: fn(ctx) {
    // Process the task...
    Complete(json.object([#("sent", json.bool(True))]))
  },
  on_error: option.None,
)

let assert Ok(poll_interval) = worker.delay_ms(1000)
let assert Ok(duration) = lease.seconds(45)
let config =
  worker.new(db, "emails", [email_handler])
  |> worker.with_poll_interval(poll_interval)
  |> worker.with_claim_expiry(lease.ExpiresAfter(duration))
  |> worker.with_batch_size(10)

// Start a single worker
let assert Ok(started) = worker.start(config)
```

### 6. Worker Pool with Supervisor

```gleam
import gleam/otp/static_supervisor

let pool = worker.pool_child_specs("email_workers", config, 4)

// pool is a List(ChildSpecification) with exactly 4 elements
let [first, second, third, fourth] = pool

let assert Ok(sup) =
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(first)
  |> static_supervisor.add(second)
  |> static_supervisor.add(third)
  |> static_supervisor.add(fourth)
  |> static_supervisor.start()
```

## API Reference

### `gabsurd/client`

Database connection management.

| Function     | Description                                        |
| ------------ | -------------------------------------------------- |
| `start(url)` | Connect to PostgreSQL and return `StartResult(Db)` |

Use the `sqlstate` field of `client.PostgresqlError` to identify database
errors. Use `client.error_message` for logs. `client.ConstraintViolated`
contains the constraint name and detail. Pog does not supply a SQLSTATE
for this case. SQLSTATE `AB001` returns `client.TaskCancelled`. SQLSTATE
`AB002` returns `client.RunAlreadyFailed(message)`.

### `gabsurd/queue`

Queue lifecycle management.

| Function                           | Description                      |
| ---------------------------------- | -------------------------------- |
| `create(db, name)`                 | Create an unpartitioned queue    |
| `create_with_mode(db, name, mode)` | Create a queue with storage mode |
| `drop(db, name)`                   | Drop a queue and all its data    |
| `list(db)`                         | List all queue names             |

Pass `queue.Unpartitioned` or `queue.Partitioned` to `create_with_mode`.

### `gabsurd/task`

Task lifecycle operations.

| Function                                               | Description                                                             |
| ------------------------------------------------------ | ----------------------------------------------------------------------- |
| `spawn(db, queue, name, params, options)`              | Create a new task                                                       |
| `claim(db, queue, worker_id, expiry, qty)`             | Claim available tasks with a `lease.ClaimExpiry`                        |
| `complete(db, queue, run_id, state)`                   | Mark a run as completed                                                 |
| `fail(db, queue, run_id, reason)`                      | Fail a run (uses queue retry policy)                                    |
| `fail_with_retry(db, queue, run_id, reason, retry_at)` | Fail a run and schedule a retry                                         |
| `cancel(db, queue, task_id)`                           | Cancel a task                                                           |
| `get_result(db, queue, task_id)`                       | Get task state, task name, headers, and terminal result as `TaskResult` |
| `retry(db, queue, task_id, options)`                   | Retry a failed task with `RetryOptions`                                 |
| `new_retry_options()`                                  | Create retry options that add one attempt to the task's limit           |
| `extend_claim(db, queue, run_id, extend_by)`           | Manually extend a claim lease (heartbeat)                               |
| `schedule_run(db, queue, run_id, defer_seconds)`       | Reschedule a run for future execution                                   |
| `new_options()`                                        | Create spawn options with a limit of five total attempts                |
| `with_max_attempts(options, n)`                        | Set the total attempt limit, including the first attempt                |
| `with_unlimited_attempts(options)`                     | Spawn a task without an attempt limit                                   |
| `with_retry_strategy(options, strategy)`               | Set retry strategy                                                      |
| `with_cancellation(options, policy)`                   | Set cancellation policy                                                 |
| `with_headers(options, json)`                          | Set headers metadata                                                    |
| `with_idempotency_key(options, key)`                   | Prevent duplicate spawning                                              |

`spawn`, `retry`, and `claim` return IDs as `task.TaskId` and `task.RunId`.
Use `TaskId` for task operations and `RunId` for run operations.
Each type wraps a `youid/uuid.Uuid`. Match `task.TaskId(id)` or
`task.RunId(id)` to get the UUID for display or storage.

A `Claim` keeps missing retry settings, headers, wake events, and event
payloads as `None`. If `max_attempts` is `None`, the task has no attempt limit.

Match the `TaskResult` from `task.get_result` to handle `Pending`, `Running`,
`Sleeping`, `Completed`, `Failed`, or `Cancelled`. All variants include
`task_name` and optional `headers`, but not task parameters. Only
`Completed` has a `result` field, and only `Failed` has a `failure_reason`
field. These JSON fields use `None` for SQL NULL and `Some("null")` for
JSON null.

For a manual `task.retry`, use `task.new_retry_options()` to add one attempt to
the task's limit. To set a new total limit, pass
`task.RetryOptions(max_attempts: option.Some(n))`. The limit must exceed the
number of attempts already made. `SpawnOptions` apply only to `task.spawn`.

### `gabsurd/event`

Event coordination for workflows.

| Function                                                  | Description       |
| --------------------------------------------------------- | ----------------- |
| `emit(db, queue, event_name, payload)`                    | Emit an event     |
| `await(db, queue, task_id, run_id, step, event, timeout)` | Wait for an event |

Both `event.await` and `context.await_event` return an `event.AwaitResult`:
`event.Received(payload)`, `event.Suspended`, or `event.TimedOut`. A JSON
null payload is `event.Received("null")`.

Use `option.None` for a wait without a deadline and `option.Some(seconds)`
for a timed wait. Use a stable, unique step name with `event.await`.
`task.claim` saves a timeout for that step, so a late event cannot change
the result on retry.

### `gabsurd/checkpoint`

Workflow checkpoint persistence.

| Function                                                        | Description                                                          |
| --------------------------------------------------------------- | -------------------------------------------------------------------- |
| `set(db, queue, task_id, step, state, run_id, extend_claim_by)` | Save a checkpoint. Pass `0` to skip lease renewal.                   |
| `get(db, queue, task_id, step, include_pending)`                | Retrieve a checkpoint and return `Result(Option(Checkpoint), Error)` |

A checkpoint's `state` is optional JSON text. Its `owner_run_id` is an
`Option(RunId)`. If no checkpoint row exists, `get` returns `Ok(None)`.

### `gabsurd/lease`

Claim expiry settings for workers and `task.claim`.

| Name                   | Description                                                           |
| ---------------------- | --------------------------------------------------------------------- |
| `ClaimExpiry`          | `ExpiresAfter(LeaseSeconds)` or `NoExpiry`                            |
| `seconds(n)`           | Check the duration (1 to 2,147,483,647 seconds) and return a `Result` |
| `to_seconds(duration)` | Read the number of seconds in a checked duration                      |
| `default_expiry`       | A lease of 30 seconds                                                 |

Use `lease.NoExpiry` only if you do not want recovery based on a lease
deadline. If a worker stops unexpectedly, the claim does not expire.

### `gabsurd/worker`

OTP worker actor for task processing.

| Type                                    | Description                                               |
| --------------------------------------- | --------------------------------------------------------- |
| `Handler(task_name, execute, on_error)` | Handler for a specific task type                          |
| `HandlerResult`                         | `Complete(json)`, `Fail(json)`, `Suspend`, or `Cancelled` |
| `DelayMs`                               | Checked worker timer delay                                |
| `Config`                                | Opaque worker configuration                               |
| `Worker`                                | Running worker handle                                     |

| Function                                | Description                                                       |
| --------------------------------------- | ----------------------------------------------------------------- |
| `new(db, queue, handlers)`              | Create config with defaults                                       |
| `delay_ms(ms)`                          | Check the delay (1 to 4,294,967,295 ms) and return a `Result`     |
| `with_poll_interval(config, delay)`     | Set poll interval with a `DelayMs` (default: 5,000 ms)            |
| `with_batch_size(config, n)`            | Set the number of concurrent task slots (default: 1)              |
| `with_claim_expiry(config, expiry)`     | Set a `lease.ClaimExpiry` (default: 30 seconds)                   |
| `with_worker_id(config, id)`            | Set the worker ID prefix                                          |
| `with_max_backoff(config, delay)`       | Set the backoff limit with a `DelayMs` (default: 60,000 ms)       |
| `start(config)`                         | Start a worker actor                                              |
| `stop(worker)`                          | Request shutdown without waiting                                  |
| `stop_and_wait(worker, ms)`             | Request shutdown and wait for active tasks and the worker to exit |
| `child_spec(config)`                    | Create supervisor child spec                                      |
| `pool_child_specs(name, config, count)` | Create N child specs for a pool                                   |

### `gabsurd/context`

Execution context passed to worker handlers.

| Type          | Description                                                   |
| ------------- | ------------------------------------------------------------- |
| `Context`     | Contains the database, queue, claim, owner, and claim expiry  |

| Function                                | Description                                   |
| --------------------------------------- | --------------------------------------------- |
| `task_id(ctx)`                          | Task's unique identifier                      |
| `run_id(ctx)`                           | Current run's unique identifier               |
| `params(ctx)`                           | Task parameters as a raw JSON string          |
| `task_name(ctx)`                        | Task name                                     |
| `attempt(ctx)`                          | Current attempt number                        |
| `claim_expiry(ctx)`                     | Lease duration or `NoExpiry`                  |
| `step(ctx, name, decoder, run)`         | Run a step unless its checkpoint exists       |
| `try_step(ctx, name, decoder, run)`     | Run a step with a callback that can fail      |
| `get_checkpoint(ctx, name)`             | Get raw JSON state for a step                 |
| `set_checkpoint(ctx, name, state)`      | Save a checkpoint and renew the lease, if set |
| `heartbeat(ctx)`                        | Check ownership and renew the lease, if set   |
| `await_event(ctx, event_name, timeout)` | Await an event and return `event.AwaitResult` |

### `gabsurd/utility`

Maintenance and introspection.

| Function                   | Description                       |
| -------------------------- | --------------------------------- |
| `cleanup_queue(db, queue)` | Run one cleanup batch for a queue |
| `get_schema_version(db)`   | Get the installed schema version  |

`cleanup_queue` returns one `CleanupResult` on success. It contains the
queue name and the numbers of deleted tasks and events.

## Architecture

```
┌──────────────────────────────────────┐
│           Your Application           │
├──────────────────────────────────────┤
│   worker.gleam   │  task.gleam       │  ← SDK Layer (hand-written)
│   context.gleam  │  queue.gleam      │
│   event.gleam    │  checkpoint.gleam │
│   utility.gleam  │                   │
├──────────────────────────────────────┤
│     internal/query.gleam (adapter)   │
│     internal/sql.gleam (generated)   │
├──────────────────────────────────────┤
│         client.gleam and Pog         │  ← Database client
├──────────────────────────────────────┤
│ PostgreSQL + absurd.sql + extension  │  ← Database
└──────────────────────────────────────┘
```

## Worker Design

Workers use the **Handler Record** pattern — each task type gets a `Handler` with:
- `task_name`: Which tasks this handler processes
- `execute`: The business logic — `fn(Context) -> HandlerResult`
- `on_error`: Optional hook for logging/metrics when execute returns `Fail`

The handler receives a `Context` with the database connection, queue, and claim
details. If you construct a `Context`, set `claim_owner` to the unique owner
string you passed to `task.claim`. Use `context.step(ctx, ...)` for
idempotent steps and `context.await_event(ctx, ...)` for event-driven workflows.

The handler returns one of these outcomes:

- `Complete(json)` marks the task as complete.
- `Fail(json)` records a failure and retries the task if attempts remain.
- `Suspend` leaves the run asleep after a workflow operation put it to sleep.
- `Cancelled` stops the handler after the database reports
  `client.TaskCancelled`. It does not cancel the task or record a failure.

The polling actor claims only enough tasks to fill free slots. Each claim
runs in a separate linked process. Each claim batch adds a unique suffix to the
worker ID in the database. The worker records a completion or failure only if the
handler still owns an active claim. This includes failures caused by a handler
panic. The worker continues to poll after a panic.

The worker checks database leases at the poll interval, even when all slots
are full. If a lease expires, the worker stops the handler and waits for its
process to exit before it reuses the slot. Absurd records `$ClaimTimeout` and
applies the retry policy when a worker polls for work. Set the claim timeout
to zero to disable lease expiry.

`worker.stop_and_wait` stops new claims and waits for active tasks to finish.
The worker continues to check leases during shutdown.
If this call times out, the worker continues to wait for the tasks.
If a supervisor kills the worker, an independent process kills each active
task, even if the handler traps exits.

### Idempotent Steps

Use a stable, unique name for each operation. For steps in a loop, add a
stable item key to the name. The `$await:` and `$await-` prefixes are for
event waits.

- On first execution, `context.step` runs the callback, decodes its result, and
  saves a checkpoint. Saving the checkpoint extends the lease.
- On retry, it decodes the saved checkpoint and skips the callback.
- If a saved checkpoint has SQL NULL state, the step returns an error without
  running the callback.
- If decoding fails, it returns `client.CheckpointDecodeError`. It does not
  save an invalid result.
- For steps without a return value, use `decode.success(Nil)`.

Use `context.try_step` when the callback returns a `Result`. An application
error returns `Error(context.StepFailed(error))` without saving a checkpoint.
An SDK error returns `Error(context.StepSdkError(error))`.

### Unknown Task Deferral

If a task has no registered handler, the worker defers it for 60 seconds
instead of marking it as failed. The worker must still own an active claim.
The database clock sets the wake time. This lets you deploy new task types
before all workers have the new handler.

### Error Backoff

On database errors during a claim or lease check, the worker backs off
exponentially up to `max_backoff` (default 60s). It resets the delay on success.

For pools, use `pool_child_specs` to generate N workers with globally unique IDs
inside a `static_supervisor`.

## Examples

### Multi-Step Workflow with Checkpoints

On retry, `context.step` skips steps with saved checkpoints. Saving a checkpoint
through the context extends an active lease. Send a heartbeat before the lease
expires during long operations. `context.set_checkpoint` and
`context.heartbeat` return `Error(client.ClaimLost)` if the claim is no longer
active, unless the task was cancelled or the run already failed. Stop the
handler if it loses its claim. Effects of work already done are not rolled back.

```gleam
import gleam/dynamic/decode
import gleam/json
import gleam/option
import gleam/result
import gabsurd/client
import gabsurd/context
import gabsurd/worker.{Cancelled, Complete, Fail, Handler}

let process_order = Handler(
  task_name: "process_order",
  execute: fn(ctx) {
    case order_workflow(ctx) {
      Ok(Nil) -> Complete(json.object([#("status", json.string("completed"))]))
      Error(client.TaskCancelled) -> Cancelled
      Error(e) -> Fail(json.string(client.error_message(e)))
    }
  },
  on_error: option.None,
)

fn order_workflow(ctx) -> Result(Nil, client.GabsurdError) {
  let params = decode_params(context.params(ctx))

  // Step 1: Charge credit card (skip if checkpoint exists)
  use _ <- result.try(context.step(ctx, "charge", decode.success(Nil), fn() {
    charge_card(params)
    json.null()
  }))

  // Step 2: Reserve inventory (skip if done)
  use _ <- result.try(context.step(ctx, "reserve", decode.success(Nil), fn() {
    reserve_inventory(params)
    json.null()
  }))

  // Step 3: Send confirmation
  use _ <- result.try(context.step(ctx, "notify", decode.success(Nil), fn() {
    send_confirmation(params)
    json.null()
  }))

  Ok(Nil)
}
```

### Steps That Pass Data Forward

```gleam
fn order_workflow(ctx) -> Result(Nil, client.GabsurdError) {
  // Charge and get back the charge_id
  use charge_id <- result.try(
    context.step(ctx, "charge", charge_id_decoder(), fn() {
      let result = charge_card(decode_params(context.params(ctx)))
      json.object([#("charge_id", json.string(result.id))])
    }),
  )

  // Use charge_id in the next step
  use _ <- result.try(context.step(ctx, "capture", decode.success(Nil), fn() {
    capture_charge(charge_id)
    json.null()
  }))

  Ok(Nil)
}

// Decoder using Gleam's continuation-based decode.field API:
fn charge_id_decoder() -> decode.Decoder(String) {
  use charge_id <- decode.field("charge_id", decode.string)
  decode.success(charge_id)
}
```

### Event-Driven Workflow

A task can suspend while it waits for an external event, such as a webhook
callback. Return `worker.Suspend` when `context.await_event` returns
`event.Suspended`. The worker can claim the run again when the event arrives
or the deadline expires. Handle `event.TimedOut` separately from
`event.Received`. On later claims, `context.await_event` returns the saved
timeout even if the event arrives late. Use `option.None` to wait without a
deadline. A wait can change database state only while the handler owns an
active claim.

```gleam
import gleam/dynamic/decode
import gleam/json
import gleam/option
import gleam/result
import gabsurd/client
import gabsurd/context
import gabsurd/event.{Received, Suspended, TimedOut}
import gabsurd/worker.{Cancelled, Complete, Fail, Handler, Suspend}

let generate_report = Handler(
  task_name: "generate_report",
  execute: fn(ctx) {
    case wait_for_report(ctx) {
      Ok(Received(payload)) -> Complete(json.string(payload))
      Ok(Suspended) -> Suspend
      Ok(TimedOut) -> Complete(json.string("report timed out"))
      Error(client.TaskCancelled) -> Cancelled
      Error(e) -> Fail(json.string(client.error_message(e)))
    }
  },
  on_error: option.None,
)

fn wait_for_report(ctx) -> Result(event.AwaitResult, client.GabsurdError) {
  use job_id <- result.try(
    context.step(ctx, "start", job_id_decoder(), fn() {
      let id = start_remote_job(context.params(ctx))
      json.object([#("job_id", json.string(id))])
    }),
  )

  context.await_event(ctx, "report_complete_" <> job_id, option.Some(3600))
}

// Decoder for the job_id stored in the checkpoint:
fn job_id_decoder() -> decode.Decoder(String) {
  use job_id <- decode.field("job_id", decode.string)
  decode.success(job_id)
}
```

Then in your webhook HTTP handler (separate process):

```gleam
import gabsurd/event

// When the remote service calls back:
let assert Ok(Nil) = event.emit(
  db, "reports",
  "report_complete_" <> job_id,  // must match event_name from await
  json.object([#("url", json.string(download_url))]),
)
```

### Idempotent Task Spawning

Use `with_idempotency_key` to prevent duplicate tasks — critical for
payment processing where double-spawning means double-charging.

```gleam
let assert Ok(info) =
  task.spawn(
    db, "payments", "charge_card",
    json.object([#("amount", json.int(9999))]),
    task.new_options()
    |> task.with_idempotency_key("order-" <> order_id),
  )
// If the caller crashes and retries, the same task is returned
// (info.created will be False on subsequent calls)
```

### Retry Strategies

```gleam
import gleam/option

// Exponential backoff between attempts
let assert Ok(_) =
  task.spawn(
    db, "integrations", "sync_crm",
    json.object([#("contact_id", json.string(id))]),
    task.new_options()
    |> task.with_max_attempts(5)
    |> task.with_retry_strategy(task.ExponentialRetry(
      base_seconds: 10, factor: 2.0, max_seconds: option.Some(300.0),
    )),
  )
// Retries at ~10s, 20s, 40s, 80s, capped at 300s
```

### Long-Running Tasks with Manual Heartbeats

For tasks that do a single long operation without checkpoints:

```gleam
import gabsurd/client
import gabsurd/context
import gabsurd/worker.{Cancelled, Complete, Fail, Handler}
import gleam/json
import gleam/list
import gleam/option
import gleam/result

let handler = Handler(
  task_name: "batch_import",
  execute: fn(ctx) {
    let outcome = list.try_each(records, fn(batch) {
      use _ <- result.try(context.heartbeat(ctx))
      process_batch(batch)
      Ok(Nil)
    })
    case outcome {
      Ok(Nil) ->
        Complete(json.object([#("imported", json.int(list.length(records)))]))
      Error(client.TaskCancelled) -> Cancelled
      Error(error) -> Fail(json.string(client.error_message(error)))
    }
  },
  on_error: option.None,
)
```

## Development

Run these commands from the repository root:

```bash
# Initialize the SQL submodule once
git submodule update --init --recursive

# Load the local database settings
source .envrc

# Start PostgreSQL and wait until it is ready
docker compose up -d --wait db

# Run tests against DATABASE_URL
gleam test
```

When the data directory is empty, PostgreSQL loads the SQL files in this order:

1. `priv/stubs.sql`
2. `vendor/absurd/sql/absurd.sql`
3. `priv/gabsurd.sql`

`gleam test` reads `DATABASE_URL`. The `db_data` volume keeps data between starts.
To reset the database run:

```bash
docker compose down --volumes &&
docker compose up -d --wait db
```

### Generate SQL bindings

Keep one query per file in `src/gabsurd/internal/sql/`. With the database
initialized as shown above and `DATABASE_URL` set, run:

```bash
gleam run -m squirrel
gleam run -m squirrel check
```

Keep the generated `src/gabsurd/internal/sql.gleam` in version control. Do not
edit it by hand.

## License

Apache-2.0
