# KRIPE

This is a proof of concept for using a SQL based approach to enable transparent, reliable, and cryptographically verifiable (blockchain-like) audit logging for Postgres tables. This is a monolithic, blocking/synchronous solution that might not be suited for very high performance, or very large transaction volume applications. But it may work very well for small to medium size data sets that require a full audit trail that is reliable, difficult to tamper with, and not eventually consistent, such as financial data or identity records.

### Requirements

* Postgres 9.6 or later 
* pgcrypto extension enabled
* uuid-ossp extension enabled

### Installation

For local installation (non-production), use the supplied Makefile for convenience,

```bash
make install
```

which will attempt to create a local database with the following
credentials:

```bash
CONN_STRING=postgres://kripe:kripe@localhost:5432/kripe
```
or simply execute the SQL files as shown in the `install` Makefile target:

```Makefile
psql -f ./src/sql/core_configuration.sql ${CONN_STRING}
psql -f ./src/sql/log_function_template.sql ${CONN_STRING}
psql -f ./src/sql/create_function.sql ${CONN_STRING}
psql -f ./src/sql/history_function.sql ${CONN_STRING}
psql -f ./src/sql/verify_function.sql ${CONN_STRING}
```

### Usage

First run the end-to-end integration tests (recommended):

```bash
make test
```

Second, create or modify the tables that require logging by making sure
they meet the following schema requirements:

* Table includes an `id BIGINT` field, ideally as a primary key.
* Table includes a `hash CHAR(66)` field for this service to use. If there is a conflict, it can be named anything else as well.

For example:
```SQL
create table example
(
    id           bigserial primary key,
    name         varchar,
    email        varchar,
    age          int,
    date_created timestamp without time zone default current_timestamp,
    hash         char(66)
)
```

Third, run the following function to enable logging:

```SQL
select __kripe_fn_create_log('example'); -- returns true
```
See the `create_function.sql` for more options on specifying a custom schema and/or hash field name. 

Fourth, run table write operations.

Finally, you can fetch the audit log for the table and record ID...

```SQL
select * from __kripe_fn_history('example', 1) -- Record ID = 1
```

```
 id | op |                                                       diff                                                        |        date_created
----+----+-------------------------------------------------------------------------------------------------------------------+----------------------------
  2 | I  | {"id": 1, "age": 41, "name": "Alice", "email": "alice@example.com", "date_created": "2017-12-07 13:15:25.762015"} | 2017-12-07 13:15:25.762015
  7 | U  | {"age": 40, "name": "Alice K."}                                                                                   | 2017-12-07 13:15:25.769537
  8 | U  | {"name": "Alice K"}                                                                                               | 2017-12-07 13:15:25.77321
 10 | U  | {"age": null, "name": "alice"}                                                                                    | 2017-12-07 13:15:25.777214
 11 | U  | {"age": 40, "name": "Alice"}                                                                                      | 2017-12-07 13:15:25.779835
  9 | U  | {"age": 100, "name": "hacker"}                                                                                    | 2017-12-07 13:15:25.775362
(6 rows)
```
** the diff shows the difference between the previous record and the current record.

...as well as verify the crypto-chain for the audit log using:

```SQL
select log_entry_id
     , computed_current_hash
     , current_hash
     , hashes_match
from __kripe_fn_verify('example', 1);
```

```
 log_entry_id |                       computed_current_hash                        |                            current_hash                            | hashes_match
--------------+--------------------------------------------------------------------+--------------------------------------------------------------------+--------------
            2 | \xe6b0df2a5def7285ad45d780134039c460ca7e0dcc90e6d3773b843058d47522 | \xe6b0df2a5def7285ad45d780134039c460ca7e0dcc90e6d3773b843058d47522 | t
            7 | \x0535fbc0e06bbbc3556f7b1fe66b8d95dfebd399ede1f01ee268f6199f450eee | \x0535fbc0e06bbbc3556f7b1fe66b8d95dfebd399ede1f01ee268f6199f450eee | t
            8 | \x533e822d105218856592e96479c055c0ab870117d8c69000c7181dd595f12408 | \x533e822d105218856592e96479c055c0ab870117d8c69000c7181dd595f12408 | t
            9 | \x228eacd3a79321e25071395fda34282b8257d550caeb51d13693c7f75b61b6b3 | \x7b7bdbabafa96d83f908c129bfbe4978d7f2259859d6dc600fed79fb27737059 | f
           10 | \x0fcc1b8cb5ebf80106f09f04ec0f1ff7c2b02e06558cac1dc4b9dc6e7274c619 | \x0fcc1b8cb5ebf80106f09f04ec0f1ff7c2b02e06558cac1dc4b9dc6e7274c619 | t
           11 | \xa82f58c0ab5d3874c90a4d44aba0bb9ca231dbba3fbac65df80dfe405c2c5653 | \xa82f58c0ab5d3874c90a4d44aba0bb9ca231dbba3fbac65df80dfe405c2c5653 | t
(6 rows)
```

In this scenario, the field `hashes_match` shows that one record was tampered with and that the entire chain is now invalid.

### Hashing Approach

Like a blockchain, each log entry hash computation combines the current entry diff with the hash of the previous entry.
In addition, a random record selected from a random distribution of the entire log is also chained into the hash computation.

The chaining for log entry `n` is then computed as:

```
H(n) = H(H(n - 1) + H(rand(1,n)) + H(diff))

s.t. H = sha256(str)
```

The first record is seeded with a randomly generated root hash stored in `_kripe_roo_hash` table for each table record.

### Performance & Optimizations

A few considerations have been made to maximize this solution's performance and reduce space utilization:

* Written in PL/PGSQL, Postgres' native routine language.
* Generalized using a templating approach: each log table receives own copy of the log creation functions
in order to avoid expensive dynamic queries and allowing postgres to optimize its performance.
* Storing diffs rather entire record snapshots in order to minimize log table space.

For very large tables, Postgres partitioning can be overlayed as a way to manage and rotate log data over time.
The current solution doesn't yet support it but it could be easily modified to use an inheritance based model
where each partition then becomes atomic and its own chain. 

### Current Benchmarks

For benchmarking in your own machine simply run:

```bash
make install && make benchmark
```

This will run a `1M` distribution of random write operations into a large table to try mimic
typical real-world scenarios with the following distribution ratios:

```
P(n) = P(inserts) + P(updates) + P(deletes) = 0.5 + 0.4 + 0.1
```

On a dual-core mackbook pro (2015), here are three runs:

Run 1
```bash
psql:./src/test/benchmark_test.sql:141: NOTICE:  performing random write operations on a log-enabled table
psql:./src/test/benchmark_test.sql:141: NOTICE:  execution time (seconds) = 448.715517
psql:./src/test/benchmark_test.sql:141: NOTICE:  inserts = 509454, updates = 400040, deletes = 90506, total writes = 1000000
DO
psql:./src/test/benchmark_test.sql:215: NOTICE:  performing random write operations on a non-log table
psql:./src/test/benchmark_test.sql:215: NOTICE:  execution time (seconds) = 161.40028
psql:./src/test/benchmark_test.sql:215: NOTICE:  inserts = 510287, updates = 399949, deletes = 89764, total writes = 1000000
```

Run 2
```bash
psql:./src/test/benchmark_test.sql:141: NOTICE:  performing random write operations on a log-enabled table
psql:./src/test/benchmark_test.sql:141: NOTICE:  execution time (seconds) = 434.157862
psql:./src/test/benchmark_test.sql:141: NOTICE:  inserts = 509822, updates = 400319, deletes = 89859, total writes = 1000000

psql:./src/test/benchmark_test.sql:215: NOTICE:  performing random write operations on a non-log table
psql:./src/test/benchmark_test.sql:215: NOTICE:  execution time (seconds) = 141.959139
psql:./src/test/benchmark_test.sql:215: NOTICE:  inserts = 509327, updates = 400969, deletes = 89704, total writes = 1000000

```

Run 3
```bash
psql:./src/test/benchmark_test.sql:141: NOTICE:  performing random write operations on a log-enabled table
psql:./src/test/benchmark_test.sql:141: NOTICE:  execution time (seconds) = 411.519971
psql:./src/test/benchmark_test.sql:141: NOTICE:  inserts = 509580, updates = 400004, deletes = 90416, total writes = 1000000
DO
psql:./src/test/benchmark_test.sql:215: NOTICE:  performing random write operations on a non-log table
psql:./src/test/benchmark_test.sql:215: NOTICE:  execution time (seconds) = 116.355814
psql:./src/test/benchmark_test.sql:215: NOTICE:  inserts = 510125, updates = 400063, deletes = 89812, total writes = 1000000
```

Summarizing these:

```
nolog / log
--------------------------------------
161.40028 / 448.715517 = 0.3596940018
141.95914 / 434.157862 = 0.326975857
116.355814 / 411.519971 = 0.2827464575

AVG = 32.31% of regular write operations
```

So, this solution yields about 1/3 of the regular postgres write performance.


However, this is because for each write operation, another write is been issued to the log.
In order to determine the overhead of just the infrastructure minus the writes, we'll need to
account for 2X writes in the log example. But how much do different writes cost?

A quick benchmark with 100K writes on a regular table with the same setup shows:

```
Inserts (secs / 100K)
---------------------
5.945083
6.414127
5.924262
AVG = 6.06 


Updates (secs / 100K)
---------------------
6.96808
7.360171
7.358508
AVG = 7.23


Deletes (secs / 100K)
---------------------
5.007005
3.725114
4.162273
AVG = 4.30
```

The overall average of a write if we assume equal distribution is `5.86` secs / 100K,
which is `96.7%` of an insert operation. Therefore, we can just double the number of writes for a ballpark
estimation for the overhead of this solution:

```
OVERHEAD = 1 - 0.3231 x 2 = 35.38%

```
Essentially a single write that took `0.16ms` in a normal table took  about `0.45ms` on the log-enabled table.

This is still not great, but considering that this solution is just a proof of concept, and that Postgres
generally yields great throughput, it may actually be a good fit for most cases where a WAL solution may not
provide the necessary log data integrity or realtime log updates that are not eventually consistent.


### Update 2020-03-07

After unarchiving this project from gitlab in order to make it public, I upgraded postgres and did a quick performance analysis at the log function feature level, by commenting out certain features and running benchmarking multiple times. 

It showed the following costs:
```
converting document to jsonb ~ 25%
fetching random salt ~ 25%
computing digest ~25%
saving log entry ~25%
```

No visible performance gains were achieved when replacing diff calculation with
just a snapshot. It seems Postgres jsonb is high performing but jsonb to text conversion seems to have
a high overhead.
