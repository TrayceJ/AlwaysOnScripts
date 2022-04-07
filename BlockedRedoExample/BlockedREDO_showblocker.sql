--this query will show the TSQL Batch that is causing a secondary
--database REDO to be blocked
SELECT DB_Name(exr.database_id) AS "DB with Blocked REDO",  
	exr.session_id AS "REDO Session ID", exr.database_id, 
	exr.blocking_session_id, stxt.text AS "TSQL batch blocking REDO"
	FROM sys.dm_exec_requests exr
	INNER JOIN sys.dm_exec_requests blck on
		exr.blocking_session_id = blck.session_id
	INNER JOIN sys.databases sd on exr.database_id = sd.database_id
	CROSS APPLY sys.dm_exec_sql_text(blck.sql_handle) stxt
	WHERE sd.group_database_id IS NOT NULL /*filter on dbs in AG*/
		AND sd.state_desc = 'ONLINE' /*databases that are online*/
		AND exr.command = 'DB Startup' /*REDO thread*/

