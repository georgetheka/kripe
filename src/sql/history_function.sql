/**
  Custom type used to represent history function result.
 */
drop type if exists _kripe_history_return_type cascade;
create type _kripe_history_return_type as (
    id bigint,
    op char(1),
    diff jsonb,
    date_created timestamp without time zone);

/**
  Displays log history for a given table, record, and time range.

  param target_table_name varchar: the name of table requiring an append log.
  param record_id: the id for the record in question.
  param start_date timestamp: time range start date.
  param end_date timestamp: time range end date.

  returns setof _kripe_history_return_type: list of log records for this record.
 */
drop function if exists __kripe_fn_history(target_table_name varchar,
    record_id bigint,
    start_date timestamp,
    end_date timestamp) cascade;
create or replace function __kripe_fn_history(target_table_name varchar,
                                              record_id bigint,
                                              start_date timestamp default to_timestamp(0),
                                              end_date timestamp default current_timestamp)
    returns setof _kripe_history_return_type as
$__kripe_fn_history__$
declare
    log_table_name constant varchar := '__' || target_table_name || '_append_log';
    r                       _kripe_history_return_type;
begin
    if start_date >= end_date then
        raise exception 'start_date (%) is equal or greater than end_date (%)',
            start_date, end_date;
    end if;

    for r in execute format(
            'select id, op, diff, date_created from %I where date_created >= $1 and date_created <= $2 and oid = $3',
            log_table_name) using start_date, end_date, record_id
        loop
            return next r;
        end loop;
end
$__kripe_fn_history__$ language plpgsql volatile;
