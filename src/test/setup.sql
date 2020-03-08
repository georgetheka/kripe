/**
  Creates and configures database.
 */

-- creates database
create database kripe;
-- creates superuser
create user kripe with password 'kripe';
alter user kripe with superuser;
