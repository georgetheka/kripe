CONN_STRING=postgres://kripe:kripe@localhost:5432/kripe

.PHONY: all
all: install test

.PHONY: install
install:
	psql -f ./src/test/setup.sql
	psql -f ./src/sql/core_configuration.sql ${CONN_STRING}
	psql -f ./src/sql/log_function_template.sql ${CONN_STRING}
	psql -f ./src/sql/create_function.sql ${CONN_STRING}
	psql -f ./src/sql/history_function.sql ${CONN_STRING}
	psql -f ./src/sql/verify_function.sql ${CONN_STRING}

.PHONY: test
test:
	psql -f ./src/test/e2e_test.sql ${CONN_STRING}

.PHONY: benchmark
benchmark:
	psql -f ./src/test/benchmark_test.sql ${CONN_STRING}
