/**
  Used internally in the log function for performance reasons.
 */
drop type if exists __kripe_rand_entry_type;
create type __kripe_rand_entry_type as (
    id bigint,
    hash char(66));


/**
  A helper table only used for routine compilation.
  It is removed afterwards.
 */
drop table if exists "__{LOG_TYPE_NAME}_append_log";
create table "__{LOG_TYPE_NAME}_append_log"
(
    id               bigserial primary key,
    rand_hash_row_id bigint,
    oid              bigint   not null,
    op               char(1)  not null,
    constraint action_type check (op = any (array ['D', 'U', 'I'])),
    diff             jsonb,
    date_created     timestamp without time zone default current_timestamp,
    hash             char(66) not null
);

/**
    A trigger returning routine that performs all log appending operations.

    This routine is never executed but used as a template by the log creation routine.
    The contents of this function acts as a generic template and generic-like variables
    are substituted to match the target table and its hash field.

    A template approach creates a function per each table and it avoids dynamic SQL queries.
    This improves performance and injection-related security.
 */
drop function if exists "__fn_{LOG_TYPE_NAME}_append_log"() cascade;
create or replace function "__fn_{LOG_TYPE_NAME}_append_log"() returns trigger as
$__fn_LOG_TYPE_NAME_append_log__$
declare
    SHA256 constant          varchar := 'sha256';
    OP_INSERT constant       varchar := 'INSERT';
    OP_UPDATE constant       varchar := 'UPDATE';
    OP_DELETE constant       varchar := 'DELETE';
    ACTION_INSERT constant   char(1) := 'I';
    ACTION_UPDATE constant   char(1) := 'U';
    ACTION_DELETE constant   char(1) := 'D';
    LT_NULL constant         varchar := 'null';
    HASH_FIELD_NAME constant varchar := '{HASH_FIELD_NAME}';
    prev_hash                varchar(66) default '';
    new_doc                  jsonb;
    old_doc                  jsonb;
    new_hash                 char(66);
    rand_hash_rec            __kripe_rand_entry_type;
    rec                      record;
    rand_salt_id             bigint;
    rand_salt_hash           varchar(66);
    action                   char(1);
begin
    -- for deletes the "new" variable will be null
    -- and assigning it to "old" will prevent generating a null hash
    -- further down below
    if tg_op = OP_DELETE then
        new = old;
    end if;

    -- fetch the previous record hash from the "old" variable
    -- available for deletes and updates
    if tg_op <> OP_INSERT then
        prev_hash := old."{HASH_FIELD_NAME}";
    end if;

    -- fetch a random hash record that will act as a salt
    -- by creating a new strand and chaining this record's logs
    -- with other record's logs
    -- this is done efficiently by first selecting the max ID from the PK sequence
    -- and choosing a random number from a range from 1 to max
    rand_hash_rec := (select (id, hash) :: __kripe_rand_entry_type
                      from "__{LOG_TYPE_NAME}_append_log"
                      where id =
                            (select (floor(
                                             (random() * (select max(id) from "__{LOG_TYPE_NAME}_append_log"))) :: bigint +
                                     1))
    );

    -- new_doc will be modified later
    -- to only capture the diff between old <> new
    -- in order to minimize space
    if new is null then
        new_doc := '{}' :: jsonb;
    else
        new_doc := to_jsonb(new);
        -- because the hash field will be part of the record
        -- we need to remove this first
        new_doc := new_doc - HASH_FIELD_NAME;
    end if;

    if tg_op = OP_INSERT then
        action := ACTION_INSERT;
    elsif tg_op = OP_UPDATE then
        action := ACTION_UPDATE;
        old_doc := to_jsonb(old);
        -- removing the hash field from the previous record
        old_doc := old_doc - HASH_FIELD_NAME;

        -- replaced my own diffing solution with this elegant approach:
        -- https://stackoverflow.com/questions/36041784/postgresql-compare-two-jsonb-objects
        for rec in select * from jsonb_each(old_doc)
            loop
                -- does new_doc contain the {key:value} object?
                -- if so, remove this key from the diff since values do not differ
                if new_doc @> jsonb_build_object(rec.key, rec.value) then
                    new_doc = new_doc - rec.key;
                    -- if a record key exists in new_doc (but values don't match)
                    -- then leave this as it is a diff
                elseif new_doc ? rec.key then
                    continue;
                else
                    -- otherwise, mark nullified fields with the keyword null
                    new_doc = new_doc || jsonb_build_object(rec.key, LT_NULL);
                end if;
            end loop;
    elsif tg_op = OP_DELETE then
        action := ACTION_DELETE;
    end if;

    -- retrieve the hash from the the random record
    rand_salt_id := rand_hash_rec.id;
    rand_salt_hash := rand_hash_rec."{HASH_FIELD_NAME}";

    -- this is where the new hash is computed for this new entry
    -- H(N) = H( H(N-1) + H(RAND(N)) + H(DIFF) )
    -- record hash has been "chained" and "salted"
    new_hash := digest(prev_hash || rand_salt_hash ||
                           -- note that when converting jsonb to text
                           -- keys are always alphabetically sorted
                           -- assuring idempotency in this operation
                       digest(new_doc :: text, SHA256) :: char(66),
                       SHA256) :: char(66);

    -- set record hash value for insert or update
    new."{HASH_FIELD_NAME}" := new_hash;

    -- finally, insert the log entry
    insert into "__{LOG_TYPE_NAME}_append_log" ("rand_hash_row_id", "oid", "op", "diff", "hash")
    values (rand_salt_id, new.id, action, new_doc, new_hash);

    if tg_op = OP_DELETE then
        return old;
    else
        return new;
    end if;
end ;
$__fn_LOG_TYPE_NAME_append_log__$ language plpgsql volatile;

-- Drop helper table, no longer needed.
drop table if exists "__{LOG_TYPE_NAME}_append_log";
