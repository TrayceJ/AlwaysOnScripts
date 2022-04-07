/*****************************************************************
  This script will create an extended event session
  that captures wait_info events for any session_ids that
  are currently performing REDO activity (the COMMAND in 
  sys.dm_exec_requests is "DB STARTUP")
  
  After creating the extended event session, it will then
  start it, run for the defined period of time (default = 60 seconds),
  and then stop the extended event session.
  
  It will leave the session present on the system - not running.
  
  After collection, the data can be viewed in SQL Server Management Studio
  (SSMS) or use TSQL to review the data.
  
  This script is provided "AS IS" with no warranties, and confers no rights.
  Use of included script samples are subject to the terms specified at
  http://www.microsoft.com/info/cpyright.htm

******************************************************************/


SET NOCOUNT ON
DECLARE @CollectDuration CHAR(8) = '00:01:00'
DECLARE @TargetXML AS XML
DECLARE @TargetPath VARCHAR(max)
DECLARE @CRLF CHAR(2) = CHAR(13) + CHAR(10)
DECLARE @REDOCount INT = 0, @SessionID INT = NULL
DECLARE @sql VARCHAR(max)
DECLARE cSessions CURSOR LOCAL STATIC READ_ONLY FOR
    SELECT session_id FROM sys.dm_exec_requests WHERE command IN ('DB Startup', 'PARALLEL REDO HELP TASK', 'PARALLEL REDO TASK')
SELECT @TargetPath = path 
    FROM sys.dm_os_server_diagnostics_log_configurations

--remove previous event session
BEGIN TRY
    DROP EVENT SESSION [CSS_wait_info] ON SERVER
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 15151 BEGIN
        SELECT 'unexpected error trying to remove CSS_wait_info event session',
            ERROR_NUMBER(), ERROR_MESSAGE()
        GOTO THE_END
    END
END CATCH


--if there are no REDO sessions to track, then exit
SELECT @REDOCount = COUNT(session_id) FROM sys.dm_exec_requests WHERE command in ('DB Startup', 'PARALLEL REDO HELP TASK', 'PARALLEL REDO TASK')
IF @REDOCount IS NULL or @REDOCount=0 BEGIN
    SELECT 'There are no REDO sessions to track....    exiting.'
    GOTO THE_END
END

--return session_id and database info
SELECT session_id, database_id, DB_NAME(database_id) AS DBName, GetDate() AS CollectTime
    FROM sys.dm_exec_requests WHERE command in ('DB Startup', 'PARALLEL REDO HELP TASK', 'PARALLEL REDO TASK');

--create Xevent session
IF @TargetPath IS NOT NULL  BEGIN
    SELECT @TargetPath = @TargetPath + 'CSS_wait_info_' + '.XEL'

    SELECT  @sql = 'ALTER EVENT SESSION [CSS_wait_info] ON SERVER ADD TARGET package0.event_file(' + 
    'SET FILENAME=''' + @TargetPath + ''',max_file_size=(1024), max_rollover_files=(5))' + @CRLF + 
    'WITH (MAX_MEMORY=4096 KB, EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,'+
    'MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,'+
    'TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)'

    CREATE EVENT SESSION [CSS_wait_info] ON SERVER 
        ADD EVENT sqlos.wait_info(
        ACTION(package0.event_sequence, sqlos.scheduler_id, sqlserver.session_id)  WHERE [opcode]=(1))

    EXEC (@sql)
END /*@targetPath IS NOT NULL*/

--set filters for the session_ids that are DB Startup
IF @REDOCount > 0 BEGIN
    SELECT @sql = 'ALTER EVENT SESSION [CSS_wait_info] ON SERVER DROP EVENT sqlos.wait_info'
    EXEC (@sql)
    SELECT @sql = 'ALTER EVENT SESSION [CSS_wait_info] ON SERVER ADD EVENT sqlos.wait_info(' + @CRLF +
        'ACTION(package0.event_sequence, sqlos.scheduler_id, sqlserver.session_id)  WHERE [opcode]=(1) '
    SELECT @sql += ' AND ('
    OPEN cSessions
    FETCH NEXT FROM cSessions INTO @SessionID
    IF @SessionID IS NOT NULL BEGIN
        SELECT @sql += '[sqlserver].[session_id]=(' + CAST(@SessionID AS VARCHAR(10)) + ')'
    END
    FETCH NEXT FROM cSessions INTO @SessionID
    WHILE @@FETCH_STATUS = 0 BEGIN
        SELECT @sql += @CRLF +
         'OR [sqlserver].[session_id]=(' + CAST(@SessionID AS VARCHAR(10)) + ')'
        FETCH NEXT FROM cSessions INTO @SessionID
    END
    CLOSE cSessions
    DEALLOCATE cSessions
    SELECT @sql += '))'
    EXEC (@sql)
END

--start the xevent capture
BEGIN TRY
    ALTER EVENT SESSION [CSS_wait_info] ON SERVER STATE=START
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() NOT IN (15151, 25705) BEGIN
        SELECT 'Unexpected error trying to start CSS_wait_info event session',
            ERROR_NUMBER(), ERROR_MESSAGE()
        GOTO THE_END
    END
END CATCH

--get actual filename generated
SELECT @TargetXML = cast(xet.target_data AS XML) FROM sys.dm_xe_sessions xes
        INNER JOIN sys.dm_xe_session_targets xet
        ON xes.address = xet.event_session_address
        WHERE xet.target_name = 'event_file' and xes.name like 'CSS_wait_info%'
SELECT  @TargetPath = @TargetXML.value('(EventFileTarget/File/@name)[1]', 'VARCHAR(MAX)')
SELECT  @TargetPath AS "Xevent Filename for this session"

--run for set time
WAITFOR DELAY @CollectDuration

--stop xevent capture
BEGIN TRY
    ALTER EVENT SESSION [CSS_wait_info] ON SERVER STATE=STOP
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() NOT IN (15151, 25704) BEGIN
        SELECT 'unexpected error trying to stop CSS_wait_info event session.',
            ERROR_NUMBER(), ERROR_MESSAGE()
        GOTO THE_END
    END
END CATCH

--Drop xevent session
BEGIN TRY
    DROP EVENT SESSION [CSS_wait_info] ON SERVER
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() NOT IN (15151) BEGIN
        SELECT 'Unexpected error trying to remove CSS_wait_info event session',
            ERROR_NUMBER(), ERROR_MESSAGE()
        GOTO THE_END
    END
END CATCH;

--TODO:  if session_ids change from the beginning to now, don't return any results

--get session_ids again for the DB Startup threads (with dbids)
SELECT session_id, database_id, DB_NAME(database_id) AS DBName, GetDate() AS CollectTime
    FROM sys.dm_exec_requests WHERE command IN ('DB Startup', 'PARALLEL REDO HELP TASK', 'PARALLEL REDO TASK');


THE_END:
Print 'finished collecting'
