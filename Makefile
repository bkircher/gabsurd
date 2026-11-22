.DEFAULT_GOAL := build

# Squirrel checks the generated SQL bindings separately.
FIND_FORMAT_SOURCES := find src test -type f -name '*.gleam' ! -path 'src/gabsurd/internal/sql.gleam'

.PHONY: lint build format format-check test clean

lint:
	gleam run -m glinter src test examples/order_workflow/src

build:
	gleam build
	cd examples/order_workflow && gleam build

format:
	$(FIND_FORMAT_SOURCES) -exec gleam format {} +

format-check:
	$(FIND_FORMAT_SOURCES) -exec gleam format --check {} +

test: format-check
	. ./.envrc && \
		docker compose up -d --wait db && \
		docker compose exec -T db psql -X -v ON_ERROR_STOP=1 \
			-U "$$DB_USER" -d "$$DB_NAME" -f - < priv/gabsurd.sql && \
		gleam run -m squirrel check && \
		gleam test

clean:
	gleam clean
	cd examples/order_workflow && gleam clean
