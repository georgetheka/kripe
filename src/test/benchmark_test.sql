/**
  TEARDOWN
 */
-- clean up previous test artifacts
drop table if exists __example_append_log cascade;
drop table if exists example cascade;
drop table if exists example_no_log cascade;
drop function if exists __fn_example_append_log;

/**
  SETUP
 */
-- create example table
create table example
(
    id           bigserial primary key,
    f1           char(36),
    f2           char(36),
    f3           char(36),
    f4           char(36),
    f5           char(36),
    f6           char(36),
    f7           char(36),
    f9           char(36),
    f10          char(36),
    f11          char(36),
    f12          char(36),
    f13          char(36),
    f14          char(36),
    f15          char(36),
    f16          char(36),
    f17          char(36),
    f18          char(36),
    f19          char(36),
    f20          char(36),
    date_created timestamp without time zone default current_timestamp,
    hash         char(66)
);

-- create another identical table that will not be logged
create table example_no_log
(
    id           bigserial primary key,
    f1           char(36),
    f2           char(36),
    f3           char(36),
    f4           char(36),
    f5           char(36),
    f6           char(36),
    f7           char(36),
    f9           char(36),
    f10          char(36),
    f11          char(36),
    f12          char(36),
    f13          char(36),
    f14          char(36),
    f15          char(36),
    f16          char(36),
    f17          char(36),
    f18          char(36),
    f19          char(36),
    f20          char(36),
    date_created timestamp without time zone default current_timestamp,
    hash         char(66)
);

-- enable logging on the first table
select __kripe_fn_create_log('example');

-- perform N random operations on the logged table
-- and measure execution time
do
$$
    declare
        i            integer     := 0;
        n            integer     := 1000000; -- 1M
        insert_count integer     := 0;
        update_count integer     := 0;
        delete_count integer     := 0;
        r            integer;
        start_time   timestamptz := clock_timestamp();
    begin
        raise notice 'performing random write operations on a log-enabled table';
        loop
            exit when i = n;
            r := floor((select random() * 100));
            -- distributions: 50% inserts, 40% updates, 10% deletes
            -- insert
            if r <= 50 then
                insert_count := insert_count + 1;
                insert into example (f1, f2, f3, f4, f5, f6, f7, f9, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19,
                                     f20)
                values (uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4());
            elsif r > 50 and r <= 90 then
                update_count := update_count + 1;
                update example
                set f1  = uuid_generate_v4(),
                    f3  = uuid_generate_v4(),
                    f5  = uuid_generate_v4(),
                    f7  = uuid_generate_v4(),
                    f9  = uuid_generate_v4(),
                    f10 = uuid_generate_v4()
                where id =
                      (select (floor(
                                       (random() * (select max(id) from example))) :: bigint +
                               1));
            else
                delete_count := delete_count + 1;
                delete
                from example
                where id =
                      (select (floor(
                                       (random() * (select max(id) from example))) :: bigint +
                               1));
            end if;

            i := i + 1;
        end loop;
        raise notice 'execution time (seconds) = %', extract(epoch from (clock_timestamp() - start_time));
        raise notice 'inserts = %, updates = %, deletes = %, total writes = %',
            insert_count, update_count, delete_count, n;
    end ;
$$ language plpgsql;

-- perform N random operations on the non-logged table
-- and measure execution time
do
$$
    declare
        i            integer     := 0;
        n            integer     := 1000000; -- 1M
        insert_count integer     := 0;
        update_count integer     := 0;
        delete_count integer     := 0;
        r            integer;
        start_time   timestamptz := clock_timestamp();
    begin
        raise notice 'performing random write operations on a non-log table';
        loop
            exit when i = n;
            r := floor((select random() * 100));
            -- distributions: 50% inserts, 40% updates, 10% deletes
            -- insert
            if r <= 50 then
                insert_count := insert_count + 1;
                insert into example_no_log (f1, f2, f3, f4, f5, f6, f7, f9, f10, f11, f12, f13, f14, f15, f16, f17, f18,
                                            f19,
                                            f20)
                values (uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4(),
                        uuid_generate_v4());
            elsif r > 50 and r <= 90 then
                update_count := update_count + 1;
                update example_no_log
                set f1  = uuid_generate_v4(),
                    f3  = uuid_generate_v4(),
                    f5  = uuid_generate_v4(),
                    f7  = uuid_generate_v4(),
                    f9  = uuid_generate_v4(),
                    f10 = uuid_generate_v4()
                where id =
                      (select (floor(
                                       (random() * (select max(id) from example_no_log))) :: bigint +
                               1));
            else
                delete_count := delete_count + 1;
                delete
                from example_no_log
                where id =
                      (select (floor(
                                       (random() * (select max(id) from example_no_log))) :: bigint +
                               1));
            end if;

            i := i + 1;
        end loop;
        raise notice 'execution time (seconds) = %', extract(epoch from (clock_timestamp() - start_time));
        raise notice 'inserts = %, updates = %, deletes = %, total writes = %',
            insert_count, update_count, delete_count, n;
    end ;
$$ language plpgsql;
