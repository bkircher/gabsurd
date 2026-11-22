.DEFAULT_GOAL := build

.PHONY: lint build test clean

lint:
	gleam run -m glinter src test examples/order_workflow/src

build:
	gleam build
	cd examples/order_workflow && gleam build

test:
	. ./.envrc && \
		docker compose up -d --wait db && \
		docker compose exec -T db psql -X -v ON_ERROR_STOP=1 \
			-U "$$DB_USER" -d "$$DB_NAME" -f - < priv/gabsurd.sql && \
		gleam run -m squirrel check && \
		gleam test

clean:
	gleam clean
	cd examples/order_workflow && gleam clean
