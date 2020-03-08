/**
  Creates the artifacts needed to enable log appending functionality.

  First, it evaluates the given table for compatibility. The requirements are:

  - id bigint: an integral unique ID (ideally primary key).
  - "[hash column]" char(66): for storing the latest hash, "hash" if not specified.

  It creates a the associative log table for a given table.
  Additionally, it creates a custom log function, triggers, and seeds the log with
  the first record.

  param target_table_name varchar: the name of table requiring an append log.
  param schema_name varchar: the schema name for this table, 'public' by default.
  param hash_field_name varchar: the name of the hash field (see requirements above), 'hash' by default.

  returns boolean: true for success, exceptions will be raised otherwise.
 */
drop function if exists __kripe_fn_create_log(target_table_name varchar, schema_name varchar, hash_field_name varchar) cascade;
create or replace function __kripe_fn_create_log(target_table_name varchar, schema_name varchar default 'public',
                                                 hash_field_name varchar default 'hash') returns boolean as
$__kripe_fn_create_log__$
declare
    LOG_TYPE_NAME_PATTERN constant   varchar := '{LOG_TYPE_NAME}';
    HASH_FIELD_NAME_PATTERN constant varchar := '{HASH_FIELD_NAME}';
    ROOT_HASH_PATTERN constant       varchar := '{ROOT_HASH_VALUE}';
    root_hash                        char(66);
    is_compatible_table              boolean;
    log_table_name                   varchar;
    routine_definition               varchar;
begin
    is_compatible_table := (select count(1) = 2
                            from information_schema.columns
                            where table_schema = schema_name
                              and table_name = target_table_name
                              and ((column_name = 'id' and data_type = 'bigint')
                                or (column_name = 'hash' and data_type = 'character' and
                                    character_maximum_length = 66)));
    if not is_compatible_table then
        raise exception
            'table % is missing required fields (id bigint, {HASH_FIELD_NAME} char(66))',
            target_table_name;
    end if;

    log_table_name := '__' || target_table_name || '_append_log';

    -- 1. Create the associating log table
    raise notice 'Creating log table %', log_table_name;
    execute format('create table %I (' ||
                   'id bigserial primary key,' ||
                   'rand_hash_row_id bigint,' ||
                   'oid bigint not null,' ||
                   'op char(1) not null,' ||
                   'constraint action_type check (op = any (array [''D'', ''U'', ''I''])),' ||
                   'diff jsonb not null,' ||
                   'date_created timestamp without time zone not null default current_timestamp,' ||
                   'hash char(66) not null)', log_table_name);

    execute format('alter table %I add constraint _kripe_fk_ foreign key ' ||
                   '(rand_hash_row_id) references %I(id) on delete cascade', log_table_name, log_table_name);

    execute format('create index on %I (rand_hash_row_id)', log_table_name);


    -- 2. Create the the root hash for this table
    execute 'delete from _kripe_root_hash where table_name = $1' using target_table_name;
    execute 'insert into _kripe_root_hash ("table_name", "hash") values ($1, $2)'
        using target_table_name, digest(uuid_generate_v4() :: char(36), 'sha256') :: char(66);

    -- fetch the root hash that was generated above
    root_hash := (select "hash" from _kripe_root_hash where "table_name" = target_table_name);

    raise notice 'Seeding table % with hash=%', log_table_name, root_hash;
    execute format('insert into %I ' ||
                   '("rand_hash_row_id", "oid", "op", "diff", "hash") ' ||
                   'values (null, $1, $2, $3, $4)', log_table_name)
        using 0, 'I', '{}' :: jsonb, root_hash;

    -- 3. Create the log-appending function
    raise notice 'Creating log-appending function %', log_table_name;
    routine_definition := replace('drop function if exists  __fn_{LOG_TYPE_NAME}_append_log()',
                                  LOG_TYPE_NAME_PATTERN, target_table_name);
    execute routine_definition;

    -- create the function definition wrapping it with the signature header and footer
    routine_definition := 'create or replace function __fn_{LOG_TYPE_NAME}_append_log() ' ||
                          'returns trigger as $__fn_LOG_TYPE_NAME_append_log__$ ' ||
                          (select t.routine_definition
                           from information_schema.routines as t
                           where t.routine_schema = 'public'
                             and routine_name = '__fn_{LOG_TYPE_NAME}_append_log') ||
                          '$__fn_LOG_TYPE_NAME_append_log__$ language plpgsql volatile';

    routine_definition := replace(routine_definition, LOG_TYPE_NAME_PATTERN, target_table_name);
    routine_definition := replace(routine_definition, ROOT_HASH_PATTERN, ROOT_HASH);
    routine_definition := replace(routine_definition, HASH_FIELD_NAME_PATTERN, hash_field_name);
    execute routine_definition;

    -- 4. Create triggers
    raise notice 'Creating log-appending trigger';
    execute 'create trigger _trigger_' ||
            target_table_name ||
            '_append_log before insert or update or delete on ' ||
            target_table_name ||
            ' for each row execute procedure __fn_' ||
            target_table_name || '_append_log()';
    return true;
end
$__kripe_fn_create_log__$ language plpgsql volatile;
