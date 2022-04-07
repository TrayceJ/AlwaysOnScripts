--BlockRedo_3.sql
-- this query (executed on secondary replica database)
-- is used to show the SCH-S and SCH-M locks that
-- cause the REDO blocking.

--change context to secondary database:

USE <dbname>
GO

--execute following query to see the SCH-S locks
select 	resource_type, request_mode, request_status
	from sys.dm_tran_locks 
	where resource_type = 'OBJECT'


--go back to blockredo_1.sql
