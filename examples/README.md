# Examples

Self-contained, runnable Gleam projects demonstrating workflow patterns with gabsurd.

| Example                              | Pattern                        | Key Concepts                                                                                 |
| ------------------------------------ | ------------------------------ | -------------------------------------------------------------------------------------------- |
| [`order_workflow/`](order_workflow/) | Full order processing pipeline | `context.step`, data passing between steps, event-driven suspend/resume, idempotent spawning |

## Running

All examples share the main project's PostgreSQL database.
Start it from the repository root:

```bash
git submodule update --init --recursive
source .envrc
docker compose up -d --wait db
```

Then use Gleam directly in the example directory:

```bash
cd examples/order_workflow
gleam build
gleam format src
gleam format --check src
gleam run -m order_workflow
```

See the [Development](../README.md#development) instructions for more.
