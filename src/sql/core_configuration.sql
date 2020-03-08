create extension if not exists pgcrypto;
create extension if not exists "uuid-ossp";

/**
  Stores the root hashes for each log table.
 */
drop table if exists _kripe_root_hash;
create table _kripe_root_hash
(
    table_name varchar(64) not null unique primary key,
    "hash"     char(66)
);
