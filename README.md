# pg_describe_resultset_sql

Pure PL/pgSQL implementation of [pg_describe_resultset](https://github.com/nick-ivanov-edb/pg_describe_resultset) — **no C compiler, no binaries, no `CREATE EXTENSION` required**.

Returns the description of the result set produced by an arbitrary SQL query: column names, type OIDs, type names, lengths and attributes — **without executing the query itself**.

This is a drop-in SQL-only companion to the C extension:

- C version (PostgreSQL 18 port): <https://github.com/zibmos-star/pg_describe_resultset>
- Original (PostgreSQL 15, by Nick Ivanov, EnterpriseDB): <https://github.com/nick-ivanov-edb/pg_describe_resultset>

## Why a separate repository?

The C extension must be compiled for every PostgreSQL major version. This PL/pgSQL version works on any modern PostgreSQL (tested on 14, 15, 16, 17 and 18) with zero build steps — just run one SQL file. Useful for:

- managed databases where you cannot install shared libraries;
- sandboxes, CI pipelines, temporary environments;
- cases where you only need column metadata and prefer no compiled objects in the cluster.

## Usage

```sql
SELECT * FROM describe_resultset(
    'SELECT 1 AS foo, ''hello'' AS bar, 3.14 AS pi'
);
```

```
 column_name | column_type | column_type_name | column_len | column_attrs
-------------+-------------+------------------+------------+--------------
 foo         |          23 | int4             |          4 |
 bar         |          25 | text             |         -1 |
 pi          |        1700 | numeric          |         -1 |
```

## Install

Run in the target database (no superuser required, needs only the default `TEMP` privilege):

```bash
psql -d your_db -f describe_resultset.sql
```

## How it works

The query is wrapped into a temporary view with `LIMIT 0`. PostgreSQL parses and plans it — so the output column metadata appears in `pg_attribute`/`pg_type` — but the underlying query is **never executed** (verified: `describe_resultset('select 1/0 as boom')` returns metadata without raising the division error).

## Differences from the C version

| | C extension | PL/pgSQL version |
|---|---|---|
| Column metadata | `SPI_tuptable->tupdesc` | temp view `LIMIT 0` + `pg_attribute` |
| Query executed? | yes, once (`SPI_execp` on PG18) | **never** |
| `column_attrs` | populated | always `NULL` |
| Duplicate output column names | allowed | error (via `CREATE VIEW`) |
| Volatility | `STABLE` | `VOLATILE` (creates temp view) |
| Install | `make && make install` + `CREATE EXTENSION` per DB | `psql -f` per DB |
| Works on managed PG (no `.so`) | no | **yes** |

`column_len` semantics match the C version (`attlen`): `int4→4`, `text/varchar→-1`, `numeric→-1`, `timestamptz→8`.

## Tests

```bash
psql -d your_db -f test_plpgsql.sql
```

9 checks: simple types, query-not-executed, table columns, idempotency, CTE/window functions, duplicate column error, broken query cleanup, no leftover probe views, cleanup.

## License

MIT — see [LICENSE](LICENSE). Based on the API of `pg_describe_resultset` by Nick Ivanov (EnterpriseDB), originally written for PostgreSQL 15.
