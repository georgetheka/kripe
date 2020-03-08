/**
  TEARDOWN
 */
-- clean up previous test artifacts
drop table if exists __example_append_log cascade;
drop table if exists example cascade;
drop function if exists __fn_example_append_log;

/**
  SETUP
 */
-- create example table
create table example
(
    id           bigserial primary key,
    name         varchar,
    email        varchar,
    age          int,
    date_created timestamp without time zone default current_timestamp,
    hash         char(66)
);

select __kripe_fn_create_log('example');


select 'Expected number of records found after seed.' as TEST;
DO
$$
    declare
        expected_num_entries int default 1;
        num_entries          int := (select count(1)
                                     from __example_append_log);
    begin
        if num_entries <> expected_num_entries then
            raise exception 'unexpected number of records after table seed - %', num_entries;
        end if;
    end;
$$ language plpgsql;


-- insert 5 records
insert into example (name, email, age)
values ('Alice', 'alice@example.com', 41), -- id = 1
       ('Bob', 'bob@example.com', 32),     -- id = 2
       ('Chin', 'chin@example.com', 27),   -- id = 3
       ('Bruce', 'bruce@example.com', 48), -- id = 4
       ('Bae', 'bae@example.com', 22); -- id = 5


select 'Expected number of log_entries found after initial insert' as TEST;
DO
$$
    declare
        expected_num_entries int default 5 + 1;
        num_entries          int := (select count(1)
                                     from __example_append_log);
    begin
        if num_entries <> expected_num_entries then
            raise exception 'unexpected number of log entries after initial insert - %', num_entries;
        end if;
    end;
$$ language plpgsql;


select 'Single log entry found after insert for a given record ID' as TEST;
DO
$$
    declare
        expected_num_entries int default 1;
        num_entries          int := (select count(1)
                                     from __kripe_fn_history('example', 1));
    begin
        if num_entries <> expected_num_entries then
            raise exception 'unexpected number of log entries after initial insert - %', num_entries;
        end if;
    end;
$$ language plpgsql;


-- update 1 record 5 times
update example
set name = 'Alice K.',
    age  = 40
where email = 'alice@example.com';
update example
set name = 'Alice K',
    age  = 40
where email = 'alice@example.com';
update example
set name = 'Alice',
    age  = 40
where email = 'alice@example.com';
update example
set name = 'alice',
    age  = null
where email = 'alice@example.com';
update example
set name = 'Alice',
    age  = 40
where email = 'alice@example.com';
-- update 2 more records
update example
set name = 'Robert'
where email = 'bob@example.com';
update example
set age = 28
where email = 'chin@example.com';


-- assert history counts for these records
select 'Expected number of log entries found for specific record ID' as TEST;
DO
$$
    declare
        expected_num_entries int default 6;
        num_entries          int := (select count(1)
                                     from __kripe_fn_history('example', 1)); -- alice
    begin
        if num_entries <> expected_num_entries then
            raise exception 'unexpected number of log entries after updates - %', num_entries;
        end if;
    end;
$$ language plpgsql;


select 'Expected number of log entries found for specific record ID' as TEST;
DO
$$
    declare
        expected_num_entries int default 2;
        num_entries          int := (select count(1)
                                     from __kripe_fn_history('example', 2)); -- bob
    begin
        if num_entries <> expected_num_entries then
            raise exception 'unexpected number of log entries after updates - %', num_entries;
        end if;
    end;
$$ language plpgsql;


select 'Expected number of log entries found for specific record ID' as TEST;
DO
$$
    declare
        expected_num_entries int default 2;
        num_entries          int := (select count(1)
                                     from __kripe_fn_history('example', 3)); -- chin
    begin
        if num_entries <> expected_num_entries then
            raise exception 'unexpected number of log entries after updates - %', num_entries;
        end if;
    end;
$$ language plpgsql;


select 'Verification result hashes match for a given record ID' as TEST;
DO
$$
    declare
    begin
        if (select count(1) from __kripe_fn_verify('example', 1) as t where hashes_match <> true) <> 0 then
            raise exception 'Unmatched hashes found for record ID = %', 1;
        end if;
        if (select count(1) from __kripe_fn_verify('example', 2) as t where hashes_match <> true) <> 0 then
            raise exception 'Unmatched hashes found for record ID = %', 2;
        end if;
        if (select count(1) from __kripe_fn_verify('example', 3) as t where hashes_match <> true) <> 0 then
            raise exception 'Unmatched hashes found for record ID = %', 3;
        end if;
        if (select count(1) from __kripe_fn_verify('example', 4) as t where hashes_match <> true) <> 0 then
            raise exception 'Unmatched hashes found for record ID = %', 4;
        end if;
        if (select count(1) from __kripe_fn_verify('example', 5) as t where hashes_match <> true) <> 0 then
            raise exception 'Unmatched hashes found for record ID = %', 5;
        end if;
    end;
$$ language plpgsql;


-- tamper with a result
update __example_append_log
set diff = '{
  "name": "hacker",
  "age": 100
}' :: jsonb
where id = (select id from __example_append_log where oid = 1 limit 1 offset 3);


select 'Verification result captures hash mismatches for a given record ID post tampering' as TEST;
DO
$$
    declare
        expected_hashes_mismatching int := 1;
        hashes_mismatching          int := (select count(1)
                                            from __kripe_fn_verify('example', 1) as t
                                            where hashes_match <> true);
    begin
        if (hashes_mismatching) <> expected_hashes_mismatching then
            raise exception 'Unexpected mismaches found for record ID = % want %, got %',
                1, expected_hashes_mismatching, hashes_mismatching;
        end if;
    end ;
$$ language plpgsql;
