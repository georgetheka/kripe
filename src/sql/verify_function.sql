/**
  Custom type used to represent verify function result.
 */
drop type if exists _kripe_verify_return_type cascade;
create type _kripe_verify_return_type as (
    row_num int,
    computed_current_hash char(66),
    current_hash char(66),
    log_entry_id bigint,
    prev_entry_id bigint,
    rand_entry_id bigint,
    prev_hash char(66),
    rand_hash char(66),
    date_created timestamp without time zone,
    hashes_match boolean);

/**
  Computes and returns the hash chain for a given table and record.

  The result contains the 'hashes_match' field, which is set to true if the computed hash
  and the current hash for the log entry match.

  param target_table_name varchar: the name of table requiring an append log.
  param record_id: the id for the record in question.

  returns setof _kripe_verify_return_type: list of log records for this record.
 */
drop function if exists __kripe_fn_verify(target_table_name varchar, record_id bigint) cascade;
create or replace function __kripe_fn_verify(target_table_name varchar, record_id bigint)
    returns setof _kripe_verify_return_type as
$__kripe_fn_history__$
declare
    log_table_name constant varchar := '__' || target_table_name || '_append_log';
    rec                     _kripe_verify_return_type;
    SQL_STMT varchar := format(
              '   with t1 as (select * from %I t1 where t1.oid = %L order by t1.id) ' ||
    '   , t2 as ( ' ||
    '    select row_number() over (order by t1.id) as row_num ' ||
    '         , t1.id ' ||
    '         , t1.hash ' ||
    '         , t1.date_created ' ||
    '         , lag(t1.id, 1) over (order by t1.id) as prev_id ' ||
    '         , lag(t1.hash, 1) over (order by t1.id) as prev_hash ' ||
    '         , t1.diff :: text as "data" ' ||
    '         , t1.rand_hash_row_id ' ||
    '    from t1) ' ||
    '   , t3 as (select row_num ' ||
    '                 , t2.id ' ||
    '                 , t2.date_created ' ||
    '                 , t2.rand_hash_row_id ' ||
    '                 , t2.hash ' ||
    '                 , t2.prev_id ' ||
    '                 , case ' ||
    '                       when row_num = 1 and prev_hash is null then ''''' ||
    '                       else prev_hash end as prev_hash ' ||
    '                 , t2.data ' ||
    '                 , case when t4.hash is null then '''' else t4.hash end as rand_hash ' ||
    '            from t2 ' ||
    '                     left outer join %I t4 on t4.id = t2.rand_hash_row_id ' ||
    ') ' ||
    'select *, computed_current_hash = current_hash as hashes_match from (select ' ||
    '        row_num ' ||
    '       , digest(prev_hash || rand_hash || digest(data, ''sha256'') :: char(66), ''sha256'') :: char(66) as computed_current_hash ' ||
    '       , hash as current_hash ' ||
    '       , id as log_entry_id' ||
    '       , prev_id as prev_entry_id ' ||
    '       , rand_hash_row_id as rand_entry_id ' ||
    '       , prev_hash ' ||
    '       , rand_hash ' ||
    '       , date_created ' ||
    '    from t3) as t4', log_table_name, record_id, log_table_name, log_table_name);
begin
    for rec in execute SQL_STMT loop
        return next rec;
    end loop;
end
$__kripe_fn_history__$ language plpgsql volatile;
