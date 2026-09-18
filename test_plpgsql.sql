-- Sanity tests for the pure PL/pgSQL describe_resultset function.
-- Run from the repo root:  psql -d your_db -f test_plpgsql.sql
-- Everything is created in schema drs_test and dropped at the end.

\set ON_ERROR_STOP on

\echo '=== 0. Server version and installation into schema drs_test ==='
show server_version;
create schema if not exists drs_test;
set search_path = drs_test, public;
\ir describe_resultset.sql

\echo '=== 1. Simple types ==='
select * from describe_resultset('select 1 as foo, ''hello'' as bar, 3.14 as pi');

\echo '=== 2. The query must NOT be executed: 1/0 in the body, but metadata is returned ==='
select * from describe_resultset('select 1/0 as boom');

\echo '=== 3. Table columns: varchar(40) -> -1, numeric(12,3) -> -1, timestamptz -> 8 ==='
create temp table t1(id int, name varchar(40), amount numeric(12,3), ts timestamptz);
select * from describe_resultset('select * from t1');

\echo '=== 4. Idempotency: repeated call in the same session ==='
select * from describe_resultset('select 1 as foo');

\echo '=== 5. CTE + window function + casts ==='
select * from describe_resultset('with t as (select 1 x) select x, x::text x_txt, array_agg(x) over () arr from t order by x');

\echo '=== 6. Duplicate column names -> expected documented error ==='
do $outer$
begin
    perform drs_test.describe_resultset('select 1 a, 2 a');
exception when others then
    raise notice 'EXPECTED error: %', sqlerrm;
end $outer$;

\echo '=== 7. Broken query -> no leftover probe view ==='
do $outer$
begin
    perform drs_test.describe_resultset('select * from _no_such_table_');
exception when others then
    raise notice 'EXPECTED error: %', sqlerrm;
end $outer$;

\echo '=== 8. No leftover probe views in pg_temp ==='
select count(*) as leftover_probe_views
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relname like '_drs_probe_%' and n.nspname like 'pg_temp%';

\echo '=== 9. Cleanup ==='
drop schema drs_test cascade;
select 'cleanup OK' as status;
