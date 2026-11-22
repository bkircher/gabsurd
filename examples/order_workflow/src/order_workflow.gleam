//// Order processing workflow — a comprehensive gabsurd example.
////
//// Demonstrates all major SDK patterns in a single realistic workflow:
////
////   1. Idempotent steps with `context.step` (charge, capture, reserve, notify)
////   2. Passing data forward between steps (charge → capture)
////   3. Event-driven coordination (await external payment webhook)
////   4. Worker setup with supervisor and pool
////
//// All business functions (`charge_card`, `capture_charge`, etc.) are
//// stubs that log to stdout. Replace them with your real logic.
////
//// ## Running
////
////   DATABASE_URL="postgresql://gabsurd:gabsurd@127.0.0.1:5432/gabsurd" \
////     gleam run -m order_workflow

import gabsurd/client
import gabsurd/context
import gabsurd/event
import gabsurd/queue
import gabsurd/task
import gabsurd/worker.{type Handler, Complete, Fail, Handler, Suspend}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/option
import gleam/result

const db_url = "postgresql://gabsurd:gabsurd@127.0.0.1:5432/gabsurd"

// ============================================================================
// Entry Point
// ============================================================================

pub fn main() -> Nil {
  io.println("=== gabsurd order_workflow example ===")
  io.println("")

  // --- 1. Connect to the database ---
  io.println("[main] Connecting to database...")
  let assert Ok(started) = client.start(db_url)
  let db = started.data
  io.println("[main] Connected.")

  // --- 2. Create the queue ---
  let assert Ok(Nil) = queue.create(db, "orders")
  io.println("[main] Queue 'orders' ensured.")

  // --- 3. Spawn the order task ---
  let order_id = "ord_001"
  let assert Ok(info) =
    task.spawn(
      db,
      "orders",
      "process_order",
      order_params(order_id:, amount: 2999, email: "alice@example.com"),
      task.new_options()
        |> task.with_max_attempts(5)
        |> task.with_idempotency_key("order-" <> order_id),
    )
  io.println("[main] Spawned task: attempt=" <> int.to_string(info.attempt))

  // --- 4. Start the worker ---
  let assert Ok(poll_interval) = worker.delay_ms(500)
  let config =
    worker.new(db, "orders", [process_order_handler()])
    |> worker.with_poll_interval(poll_interval)
    |> worker.with_batch_size(10)

  let assert Ok(started) = worker.start(config)
  let running_worker = started.data
  io.println("[main] Worker started.")
  io.println("[main] Waiting for steps 1-3 (charge, capture, reserve)...")
  io.println("")

  // The worker will:
  //   - claim the task
  //   - run step 1 (charge_card)         → checkpoint saved
  //   - run step 2 (capture_charge)      → checkpoint saved
  //   - run step 3 (reserve_inventory)   → checkpoint saved
  //   - hit step 4 (await_event)         → no event yet → Suspended
  //
  // Give the worker time to process through steps 1-3 and suspend.
  process.sleep(3000)

  // --- 5. Emit the payment confirmation event (simulating a webhook) ---
  io.println("")
  io.println("[main] Emitting payment_confirmed event (simulating webhook)...")
  let assert Ok(Nil) =
    event.emit(
      db,
      "orders",
      "payment_confirmed_" <> order_id,
      json.object([#("confirmation", json.string("pay_confirm_xyz"))]),
    )

  // The sleeping task wakes up. The worker claims it again on the next poll.
  // Steps 1-3 are skipped (checkpoints exist), the event is now available
  // so step 4 succeeds, and step 5 (send_confirmation) runs.
  io.println("[main] Waiting for task to complete (steps 4-5)...")
  process.sleep(3000)

  // --- 6. Check the result ---
  let assert Ok(task_result) = task.get_result(db, "orders", info.task_id)
  io.println("")
  case task_result {
    task.Completed(result: payload, ..) ->
      io.println(
        "[main] Task completed: " <> option.unwrap(payload, "(no result)"),
      )
    task.Failed(failure_reason: reason, ..) ->
      io.println("[main] Task failed: " <> option.unwrap(reason, "(no reason)"))
    task.Cancelled(..) -> io.println("[main] Task cancelled.")
    task.Pending(..) | task.Running(..) | task.Sleeping(..) ->
      io.println("[main] Task has not finished.")
  }

  // --- 7. Clean up ---
  let assert Ok(Nil) = worker.stop_and_wait(running_worker, 5000)
  io.println("")
  io.println("=== Done! ===")
}

// ============================================================================
// Handler
// ============================================================================

/// The worker handler that dispatches to our workflow.
fn process_order_handler() -> Handler {
  Handler(
    task_name: "process_order",
    execute: execute_order,
    on_error: option.Some(fn(ctx, reason) {
      io.println("[on_error] task failed: " <> context.task_name(ctx))
      io.println("[on_error] reason: " <> json.to_string(reason))
    }),
  )
}

fn execute_order(ctx: context.Context) -> worker.HandlerResult {
  case json.parse(from: context.params(ctx), using: order_params_decoder()) {
    Error(error) -> Fail(json.string(order_params_error_message(error)))
    Ok(params) ->
      case order_workflow(ctx, params) {
        Ok(Done) ->
          Complete(json.object([#("status", json.string("completed"))]))
        Ok(WaitEvent) -> Suspend
        Ok(PaymentTimedOut) ->
          Complete(json.object([#("status", json.string("payment_timed_out"))]))
        Error(client.TaskCancelled) -> worker.Cancelled
        Error(error) -> Fail(json.string(client.error_message(error)))
      }
  }
}

// ============================================================================
// Workflow Result Type
// ============================================================================

/// Outcome of the order workflow.
type WorkflowResult {
  Done
  WaitEvent
  PaymentTimedOut
}

// ============================================================================
// Workflow — the core durable pipeline
// ============================================================================

/// Multi-step order processing workflow.
///
/// Each call to `context.step` is idempotent: if the worker crashes
/// mid-workflow and the task is retried, already-completed steps are
/// skipped automatically.
///
/// Steps:
///   1. Charge the card and get back a charge_id
///   2. Capture the charge using that charge_id
///   3. Reserve inventory
///   4. Wait for external payment confirmation (event-driven)
///   5. Send confirmation email
fn order_workflow(
  ctx: context.Context,
  params: OrderParams,
) -> Result(WorkflowResult, client.GabsurdError) {
  // Step 1: Charge the card — returns a charge_id for the next step.
  // On retry, the checkpoint is loaded and charge_card is NOT called again.
  use charge_id <- result.try(
    context.step(ctx, "charge", charge_id_decoder(), fn() {
      let id = charge_card(params.order_id, params.amount)
      json.object([#("charge_id", json.string(id))])
    }),
  )

  // Step 2: Capture the charge using the charge_id from step 1.
  use _ <- result.try(
    context.step(ctx, "capture", decode.success(Nil), fn() {
      capture_charge(charge_id)
      json.null()
    }),
  )

  // Step 3: Reserve inventory.
  use _ <- result.try(
    context.step(ctx, "reserve", decode.success(Nil), fn() {
      reserve_inventory(params.order_id)
      json.null()
    }),
  )

  // Step 4: Wait for an external payment confirmation webhook.
  // This suspends the task if the event hasn't arrived yet.
  case
    context.await_event(
      ctx,
      "payment_confirmed_" <> params.order_id,
      option.Some(3600),
    )
  {
    Ok(event.Received(_payload)) -> {
      // Event arrived — continue to step 5.
      use _ <- result.try(
        context.step(ctx, "notify", decode.success(Nil), fn() {
          send_confirmation(params.email, params.order_id)
          json.null()
        }),
      )
      Ok(Done)
    }
    Ok(event.Suspended) -> {
      // No event yet — the worker will leave this task sleeping.
      // When the event fires, this handler runs again and all
      // previous steps are skipped via checkpoints.
      Ok(WaitEvent)
    }
    Ok(event.TimedOut) -> Ok(PaymentTimedOut)
    Error(e) -> Error(e)
  }
}

// ============================================================================
// Decoders
// ============================================================================

/// Decoder for the charge_id returned by step 1.
/// Uses Gleam's continuation-based decode.field API.
fn charge_id_decoder() -> decode.Decoder(String) {
  use charge_id <- decode.field("charge_id", decode.string)
  decode.success(charge_id)
}

/// Decoder for the full order params JSON.
fn order_params_decoder() -> decode.Decoder(OrderParams) {
  use order_id <- decode.field("order_id", decode.string)
  use amount <- decode.field("amount", decode.int)
  use email <- decode.field("email", decode.string)
  decode.success(OrderParams(order_id:, amount:, email:))
}

fn order_params_error_message(error: json.DecodeError) -> String {
  case error {
    json.UnableToDecode(_) ->
      "Invalid order parameters: expected order_id, amount, and email"
    json.UnexpectedEndOfInput
    | json.UnexpectedByte(_)
    | json.UnexpectedSequence(_) ->
      "Invalid order parameters: expected valid JSON"
  }
}

// ============================================================================
// Fake Business Functions (stubs that log)
// ============================================================================

/// Simulates charging a credit card. Returns a fake charge ID.
fn charge_card(order_id: String, amount: Int) -> String {
  let id = "ch_" <> order_id
  io.println(
    "[charge_card] Charging $"
    <> format_cents(amount)
    <> " for order "
    <> order_id,
  )
  io.println("[charge_card] Created charge: " <> id)
  id
}

/// Simulates capturing a previously authorized charge.
fn capture_charge(charge_id: String) -> Nil {
  io.println("[capture_charge] Capturing charge: " <> charge_id)
  Nil
}

/// Simulates reserving inventory for an order.
fn reserve_inventory(order_id: String) -> Nil {
  io.println("[reserve_inventory] Reserving stock for order: " <> order_id)
  Nil
}

/// Simulates sending a confirmation email.
fn send_confirmation(email: String, order_id: String) -> Nil {
  io.println(
    "[send_confirmation] Sending email to "
    <> email
    <> " for order "
    <> order_id,
  )
  Nil
}

// ============================================================================
// Helpers
// ============================================================================

/// Build order params JSON.
fn order_params(
  order_id order_id: String,
  amount amount: Int,
  email email: String,
) -> json.Json {
  json.object([
    #("order_id", json.string(order_id)),
    #("amount", json.int(amount)),
    #("email", json.string(email)),
  ])
}

/// Parsed order parameters.
type OrderParams {
  OrderParams(order_id: String, amount: Int, email: String)
}

/// Format cents as a dollar string, e.g. 2999 → "29.99".
fn format_cents(n: Int) -> String {
  let dollars = n / 100
  let cents = n % 100
  int.to_string(dollars) <> "." <> pad2(cents)
}

fn pad2(n: Int) -> String {
  case n < 10 {
    True -> "0" <> int.to_string(n)
    False -> int.to_string(n)
  }
}
