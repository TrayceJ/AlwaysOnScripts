--on primary database (in an availability group)
--change context to primary replica database:

USE <dbname>
GO

--create a table
create table blockredo (f1 int)
go
--insert 35K records
insert into blockredo select 1
GO
insert into blockredo select * from blockredo
go 15
select count(*) from blockredo
GO

--keep this window open on primary
-- go to BlockRedo_2.sql (connected to secondary).
-- (you will then go to blockredo_3.sql 
--  to see the SCH-S locks held by blockredo_2.sql.
--  after viewing the SCH-S locks by blockredo_3.sql,
-- come back to this point)


--now we will cause a DDL action on the primary
--which will not get blocked on the primary

--change the datatype
alter table blockredo alter column f1 bigint
--command finishes immediately.
--go back to blockredo_3 and re-run query to show locks held

--after coming back from blockredo_3 and seeing the SCH-M lock in WAIT state (blocked)
--issue following command to generate some data, and see that the REDO QUEUE SIZE is building

update blockredo set f1 = 4
update blockredo set f1 = 5
update blockredo set f1 = 6

SELECT ags.name as AGGroupName,
    ar.replica_server_name as InstanceName,
    hars.role_desc, drs.redo_queue_size, 
    CASE drs.is_local WHEN 1 THEN db_name(drs.database_id) 
        ELSE NULL END as DBName, drs.database_id,
    ar.availability_mode_desc as SyncMode,
    drs.synchronization_state_desc as SyncState,
    drs.last_hardened_lsn, drs.end_of_log_lsn, drs.last_redone_lsn,
    drs.last_hardened_time, drs.last_redone_time,
    drs.log_send_queue_size, drs.redo_queue_size
    FROM sys.dm_hadr_database_replica_states drs
    LEFT JOIN sys.availability_replicas ar 
        ON drs.replica_id = ar.replica_id
    LEFT JOIN sys.availability_groups ags 
        ON ar.group_id = ags.group_id
    LEFT JOIN sys.dm_hadr_availability_replica_states hars
        ON ar.group_id = hars.group_id and ar.replica_id = hars.replica_id
    ORDER BY ags.name, group_database_id, hars.role_desc, ar.replica_server_name


--now go back to blockredo_2.sql and cancel query and then come back here
--this will cancel the blocked redo condition.


--after cancelling the query in blockredo_2.sql,
--execute the following query again to show the redo_queue_size
--decreasing or 0
SELECT ags.name as AGGroupName,
    ar.replica_server_name as InstanceName,
    hars.role_desc, drs.redo_queue_size, 
    CASE drs.is_local WHEN 1 THEN db_name(drs.database_id) 
        ELSE NULL END as DBName, drs.database_id,
    ar.availability_mode_desc as SyncMode,
    drs.synchronization_state_desc as SyncState,
    drs.last_hardened_lsn, drs.end_of_log_lsn, drs.last_redone_lsn,
    drs.last_hardened_time, drs.last_redone_time,
    drs.log_send_queue_size, drs.redo_queue_size
    FROM sys.dm_hadr_database_replica_states drs
    LEFT JOIN sys.availability_replicas ar 
        ON drs.replica_id = ar.replica_id
    LEFT JOIN sys.availability_groups ags 
        ON ar.group_id = ags.group_id
    LEFT JOIN sys.dm_hadr_availability_replica_states hars
        ON ar.group_id = hars.group_id and ar.replica_id = hars.replica_id
    ORDER BY ags.name, group_database_id, hars.role_desc, ar.replica_server_name


--finally -- go back to blockredo_3.sql and re-issue query looking for locks
--you should see that the Sch-S and the Sch-M locks are gone.


