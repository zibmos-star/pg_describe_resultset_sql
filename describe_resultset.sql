-- pg_describe_resultset: pure PL/pgSQL version (no C library required)
--
-- Standalone replacement for the C extension's describe_resultset() function.
-- Returns the same columns as the C version:
--   column_name, column_type (OID), column_type_name, column_len, column_attrs
--
-- How it works:
--   The query is wrapped into a temporary view with LIMIT 0, so PostgreSQL
--   parses/analyses it and exposes the output columns in pg_attribute.
--   Metadata is then read from pg_attribute/pg_type. The underlying query
--   is NEVER executed (the view is only created, never selected from).
--
-- Install (per database):  psql -f describe_resultset_plpgsql.sql
-- Usage:
--   SELECT * FROM describe_resultset('SELECT 1 AS foo, ''hello'' AS bar');
--
-- Tested on PostgreSQL 18.3.
-- Limitations vs the C version:
--   * duplicate output column names raise an error (CREATE VIEW requirement)
--   * column_attrs is always NULL
--   * function is VOLATILE (it creates/drops a temp view), the C one is STABLE
--   * requires the TEMP privilege on the database (granted by default)

create or replace function describe_resultset(sql text)
returns table (
    column_name      name,
    column_type      oid,
    column_type_name text,
    column_len       integer,
    column_attrs     text
)
language plpgsql
volatile
strict
as $fn$
declare
    v_probe text := '_drs_probe_' || pg_backend_pid();
begin
    -- тихая очистка залипшего probe-view после неудачного предыдущего вызова (без NOTICE)
    if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where c.relname = v_probe and n.nspname like 'pg_temp%') then
        execute format('drop view %I', v_probe);
    end if;
    execute format(
        'create temp view %I as select * from (%s) _q limit 0',
        v_probe, rtrim(sql, '; '));

    return query execute format(
        'select a.attname,
                a.atttypid,
                t.typname::text,
                a.attlen::integer,
                null::text
           from pg_attribute a
           join pg_type t on t.oid = a.atttypid
          where a.attrelid = %L::regclass
            and a.attnum > 0
            and not a.attisdropped
          order by a.attnum', v_probe);

    execute format('drop view if exists %I', v_probe);
end;
$fn$;
