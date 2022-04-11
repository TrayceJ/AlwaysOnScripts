/*=====================================================================
AUTHOR:     trayce@jordanhome.net
FILENAME:   Shred_system_health_XEL.sql
NOTES:
  use the CTRL-SHIFT-M macro substitution

  Database_name -- where the shredding script will store its data
                                okay for database to already to exist.
                                If the destination tables exist, they will be truncated and reloaded.

  XEL Folder path -- the path (relative to the SQL instance) of where the
                                *system_health_*.XEL files are located

  XEL File              -- filename (or wild card specification) of file to be shredded
                                by default the wildcard is "*system_health_*.xel" to shred
                                all system health XEL files in the specified folder.

TABLES OUTPUT
==============
SH_connect_RB                                           --connect ring buffer events
SH_error_reported                                       --error reported events (include "info")
SH_SchdMon_Deadlock_RB                          --scheduler monitor deadlock ring buffer events
SH_SchdMon_NonYield_RB                          --non-yielding scheduler ring buffer events
SH_SchdMon_NonYield_RM_RB                   --non-yielding resource monitor ring buffer events
SH_SchdMon_SysHealth_RB                     --system health ring buffer events
SH_security_error_ring_buffer_recorded      --security error ring buffer events
SH_sp_svr_diag_IO                                       --server diagnostics IO data
SH_sp_svr_diag_query                                    --server diagnostics query data
SH_sp_svr_diag_resource                         --server diagnostics resource data
SH_sp_svr_diag_system                               --server diagnostics system data
SH_wait_info                                                --wait info events
SH_wait_info_ext                                            --wait info external events
SystemHealth_XELData                                --raw XEL data imported

CHANGE HISTORY:
---------------------------
2015/08/12
        Changed all TimeStamp fieldnames to TimeStampUTC

2015/07/28
        Added these notes at top of script.
======================================================================*/
SET NOCOUNT ON
USE [master]
GO
BEGIN TRY
    CREATE DATABASE [<Database_Name, sysname, Case_Number>]
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 1801 BEGIN
        SELECT ERROR_NUMBER(), ERROR_MESSAGE()
        RAISERROR ('Severe error.  Terminating connection...', 19, 1) WITH LOG
    END
END CATCH
GO
BEGIN TRY
    ALTER DATABASE [<Database_Name, sysname, Case_Number>] SET RECOVERY SIMPLE
    --ALTER DATABASE [<Database_Name, sysname, Case_Number>] MODIFY FILE ( NAME = N'<Database_Name, sysname, Case_Number>', SIZE = 5120000KB )
    --ALTER DATABASE [<Database_Name, sysname, Case_Number>] MODIFY FILE ( NAME = N'<Database_Name, sysname, Case_Number>_log', SIZE = 5120000KB )
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 5039) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    RAISERROR ('Severe error.  Terminating connection...', 19, 1) WITH LOG
    END
END CATCH

USE [<Database_Name, sysname, Case_Number>] 

--construct path & file name for SQLDIAG_*.xel files to load
DECLARE @XELPath VARCHAR(max) = '<XEL Folder Path, varchar(max), D:\Path\Where\XEL Files are stored\>'
IF RIGHT(@XELPath, 1) <> '\'
    SELECT @XELPath += '\'
DECLARE @XELFile VARCHAR(max) = @XELPath + '<XELFile, varchar(max), *system_health_*.xel>'

--create table, indexes and views
BEGIN TRY
CREATE TABLE SystemHealth_XELData
    (ID INT IDENTITY PRIMARY KEY CLUSTERED,
    object_name varchar(max),
    EventData XML,
    file_name varchar(max),
    file_offset bigint);
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SystemHealth_XELData
        DROP INDEX sXML ON SystemHealth_XELData
        DROP INDEX pXML ON SystemHealth_XELData
    END ELSE 
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--load the data
INSERT INTO SystemHealth_XELData
SELECT object_name, cast(event_data as XML) AS EventData,
  file_name, File_Offset
  FROM sys.fn_xe_file_target_read_file(
  @XELFile, NULL, null, null);


--create indexes
CREATE PRIMARY XML INDEX pXML ON SystemHealth_XELData(EventData);
CREATE XML INDEX sXML 
    ON SystemHealth_XELData (EventData)
    USING XML INDEX pXML FOR PATH ;

--populate table SH_security_error_ring_buffer_recorded 
--to process security_error_ring_buffer_recorded events
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[3]', 'int') AS SessionID,
    EventData.value('(event/data/value)[4]', 'varchar(max)') AS error_code,
    EventData.value('(event/data/value)[5]', 'varchar(max)') AS api_name,
    EventData.value('(event/data/value)[6]', 'varchar(max)') AS calling_api_name,
    EventData
    INTO SH_security_error_ring_buffer_recorded
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'security_error_ring_buffer_recorded'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_security_error_ring_buffer_recorded
        INSERT INTO SH_security_error_ring_buffer_recorded
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'int') AS SessionID,
        EventData.value('(event/data/value)[4]', 'varchar(max)') AS error_code,
        EventData.value('(event/data/value)[5]', 'varchar(max)') AS api_name,
        EventData.value('(event/data/value)[6]', 'varchar(max)') AS calling_api_name,
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'security_error_ring_buffer_recorded'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--populate table SH_wait_info to process wait_info events
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/text)[1]', 'varchar(max)') AS WaitType,
    EventData.value('(event/data/text)[2]', 'varchar(max)') AS OpCode,
    EventData.value('(event/data/value)[3]', 'varchar(max)') AS duration,
    EventData.value('(event/data/value)[4]', 'varchar(max)') AS signal_duration,
    EventData.value('(event/action/value)[2]', 'varchar(max)') AS session_id,
    EventData.value('(event/action/value)[3]', 'varchar(max)') AS SQLText,
    EventData
    INTO SH_wait_info
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'wait_info'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_wait_info
        INSERT INTO SH_wait_info
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/text)[1]', 'varchar(max)') AS WaitType,
        EventData.value('(event/data/text)[2]', 'varchar(max)') AS OpCode,
        EventData.value('(event/data/value)[3]', 'varchar(max)') AS duration,
        EventData.value('(event/data/value)[4]', 'varchar(max)') AS signal_duration,
        EventData.value('(event/action/value)[2]', 'varchar(max)') AS session_id,
        EventData.value('(event/action/value)[3]', 'varchar(max)') AS SQLText,
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'wait_info'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--populate table SH_error_reported to process error_reported events
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[1]', 'bigint') AS error_number,
    EventData.value('(event/data/value)[2]', 'bigint') AS severity,
    EventData.value('(event/data/value)[3]', 'bigint') AS state,
    EventData.value('(event/data/value)[4]', 'varchar(max)') AS user_defined,
    EventData.value('(event/data/text)[1]', 'varchar(max)') AS category,
    EventData.value('(event/data/text)[2]', 'varchar(max)') AS destination,
    EventData.value('(event/data/value)[7]', 'varchar(max)') AS is_intercepted,
    EventData.value('(event/data/value)[8]', 'varchar(max)') AS message,
    EventData.value('(event/action/value)[2]', 'varchar(max)') AS session_id,
    EventData.value('(event/action/value)[3]', 'varchar(max)') AS database_id,
    EventData
    INTO SH_error_reported
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'error_reported'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_error_reported
        INSERT INTO SH_error_reported
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[1]', 'bigint') AS error_number,
        EventData.value('(event/data/value)[2]', 'bigint') AS severity,
        EventData.value('(event/data/value)[3]', 'bigint') AS state,
        EventData.value('(event/data/value)[4]', 'varchar(max)') AS user_defined,
        EventData.value('(event/data/text)[1]', 'varchar(max)') AS category,
        EventData.value('(event/data/text)[2]', 'varchar(max)') AS destination,
        EventData.value('(event/data/value)[7]', 'varchar(max)') AS is_intercepted,
        EventData.value('(event/data/value)[8]', 'varchar(max)') AS message,
        EventData.value('(event/action/value)[2]', 'varchar(max)') AS session_id,
        EventData.value('(event/action/value)[3]', 'varchar(max)') AS database_id,
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'error_reported'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--populate table SH_SchdMon_Deadlock_RB to process 
--scheduler_monitor_deadlock_ring_buffer_recorded events
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[3]', 'varchar(max)') AS OpCodeVal,
    EventData.value('(event/data/value)[4]', 'int') AS NodeID,
    EventData.value('(event/data/value)[5]', 'int') AS ProcessUtilization,
    EventData.value('(event/data/value)[6]', 'int') AS SystemIdle,
    EventData.value('(event/data/value)[7]', 'varchar(max)') AS UserModeTime,
    EventData.value('(event/data/value)[8]', 'varchar(max)') AS KernelModeTime,
    EventData.value('(event/data/value)[9]', 'varchar(max)') AS PageFaults,
    EventData.value('(event/data/value)[10]', 'varchar(max)') AS WorkingSetDelta,
    EventData.value('(event/data/value)[11]', 'varchar(max)') AS MemoryUtilization,
    EventData.value('(event/data/value)[12]', 'varchar(max)') AS CallStack,
    EventData
    INTO SH_SchdMon_Deadlock_RB
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'scheduler_monitor_deadlock_ring_buffer_recorded'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_SchdMon_Deadlock_RB
        INSERT INTO SH_SchdMon_Deadlock_RB
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'varchar(max)') AS OpCodeVal,
        EventData.value('(event/data/value)[4]', 'int') AS NodeID,
        EventData.value('(event/data/value)[5]', 'int') AS ProcessUtilization,
        EventData.value('(event/data/value)[6]', 'int') AS SystemIdle,
        EventData.value('(event/data/value)[7]', 'varchar(max)') AS UserModeTime,
        EventData.value('(event/data/value)[8]', 'varchar(max)') AS KernelModeTime,
        EventData.value('(event/data/value)[9]', 'varchar(max)') AS PageFaults,
        EventData.value('(event/data/value)[10]', 'varchar(max)') AS WorkingSetDelta,
        EventData.value('(event/data/value)[11]', 'varchar(max)') AS MemoryUtilization,
        EventData.value('(event/data/value)[12]', 'varchar(max)') AS CallStack,
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'scheduler_monitor_deadlock_ring_buffer_recorded'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--populate table SH_SchdMon_NonYield_RB to process 
--scheduler_monitor_non_yielding_ring_buffer_recorded events
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[3]', 'varchar(max)') AS OpCodeVal,
    EventData.value('(event/data/value)[4]', 'int') AS NodeID,
    EventData.value('(event/data/value)[5]', 'varchar(max)') AS Scheduler,
    EventData.value('(event/data/value)[6]', 'varchar(max)') AS Worker,
    EventData.value('(event/data/value)[7]', 'varchar(max)') AS Yields,
    EventData.value('(event/data/value)[8]', 'varchar(max)') AS WorkerUtilization,
    EventData.value('(event/data/value)[9]', 'varchar(max)') AS ProcessUtilization,
    EventData.value('(event/data/value)[10]', 'varchar(max)') AS SystemIdle,
    EventData.value('(event/data/value)[11]', 'varchar(max)') AS UserModeTime,
    EventData.value('(event/data/value)[12]', 'varchar(max)') AS KernelModeTime,
    EventData.value('(event/data/value)[13]', 'varchar(max)') AS PageFaults,
    EventData.value('(event/data/value)[14]', 'varchar(max)') AS WorkingSetDelta,
    EventData.value('(event/data/value)[15]', 'varchar(max)') AS MemoryUtilization,
    EventData.value('(event/data/value)[16]', 'varchar(max)') AS CallStack,
    EventData
    INTO SH_SchdMon_NonYield_RB
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'scheduler_monitor_non_yielding_ring_buffer_recorded'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_SchdMon_NonYield_RB
        INSERT INTO SH_SchdMon_NonYield_RB
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'varchar(max)') AS OpCodeVal,
        EventData.value('(event/data/value)[4]', 'int') AS NodeID,
        EventData.value('(event/data/value)[5]', 'varchar(max)') AS Scheduler,
        EventData.value('(event/data/value)[6]', 'varchar(max)') AS Worker,
        EventData.value('(event/data/value)[7]', 'varchar(max)') AS Yields,
        EventData.value('(event/data/value)[8]', 'varchar(max)') AS WorkerUtilization,
        EventData.value('(event/data/value)[9]', 'varchar(max)') AS ProcessUtilization,
        EventData.value('(event/data/value)[10]', 'varchar(max)') AS SystemIdle,
        EventData.value('(event/data/value)[11]', 'varchar(max)') AS UserModeTime,
        EventData.value('(event/data/value)[12]', 'varchar(max)') AS KernelModeTime,
        EventData.value('(event/data/value)[13]', 'varchar(max)') AS PageFaults,
        EventData.value('(event/data/value)[14]', 'varchar(max)') AS WorkingSetDelta,
        EventData.value('(event/data/value)[15]', 'varchar(max)') AS MemoryUtilization,
        EventData.value('(event/data/value)[16]', 'varchar(max)') AS CallStack,
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'scheduler_monitor_non_yielding_ring_buffer_recorded'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--populate table SH_SchdMon_NonYield_RM_RB to process 
--scheduler_monitor_non_yielding_rm_ring_buffer_recorded events
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[3]', 'varchar(max)') AS OpCodeVal,
    EventData.value('(event/data/value)[4]', 'int') AS NodeID,
    EventData.value('(event/data/value)[5]', 'varchar(max)') AS Worker,
    EventData.value('(event/data/value)[6]', 'varchar(max)') AS Yields,
    EventData.value('(event/data/value)[7]', 'varchar(max)') AS WorkerUtilization,
    EventData.value('(event/data/value)[8]', 'varchar(max)') AS ProcessUtilization,
    EventData.value('(event/data/value)[9]', 'varchar(max)') AS SystemIdle,
    EventData.value('(event/data/value)[10]', 'varchar(max)') AS UserModeTime,
    EventData.value('(event/data/value)[11]', 'varchar(max)') AS KernelModeTime,
    EventData.value('(event/data/value)[12]', 'varchar(max)') AS PageFaults,
    EventData.value('(event/data/value)[13]', 'varchar(max)') AS WorkingSetDelta,
    EventData.value('(event/data/value)[14]', 'varchar(max)') AS MemoryUtilization,
    EventData.value('(event/data/value)[15]', 'varchar(max)') AS MemoryAllocation,
    EventData.value('(event/data/value)[16]', 'varchar(max)') AS CallStack,
    EventData
    INTO SH_SchdMon_NonYield_RM_RB
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'scheduler_monitor_non_yielding_rm_ring_buffer_recorded'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_SchdMon_NonYield_RM_RB
        INSERT INTO SH_SchdMon_NonYield_RM_RB
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'varchar(max)') AS OpCodeVal,
        EventData.value('(event/data/value)[4]', 'int') AS NodeID,
        EventData.value('(event/data/value)[5]', 'varchar(max)') AS Worker,
        EventData.value('(event/data/value)[6]', 'varchar(max)') AS Yields,
        EventData.value('(event/data/value)[7]', 'varchar(max)') AS WorkerUtilization,
        EventData.value('(event/data/value)[8]', 'varchar(max)') AS ProcessUtilization,
        EventData.value('(event/data/value)[9]', 'varchar(max)') AS SystemIdle,
        EventData.value('(event/data/value)[10]', 'varchar(max)') AS UserModeTime,
        EventData.value('(event/data/value)[11]', 'varchar(max)') AS KernelModeTime,
        EventData.value('(event/data/value)[12]', 'varchar(max)') AS PageFaults,
        EventData.value('(event/data/value)[13]', 'varchar(max)') AS WorkingSetDelta,
        EventData.value('(event/data/value)[14]', 'varchar(max)') AS MemoryUtilization,
        EventData.value('(event/data/value)[15]', 'varchar(max)') AS MemoryAllocation,
        EventData.value('(event/data/value)[16]', 'varchar(max)') AS CallStack,
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'scheduler_monitor_non_yielding_rm_ring_buffer_recorded'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--populate table SH_SchdMon_SysHealth_RB to process scheduler_monitor_system_health_ring_buffer_recorded events
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[3]', 'varchar(max)') AS ProcessUtilization,
    EventData.value('(event/data/value)[4]', 'varchar(max)') AS SystemIdle,
    EventData.value('(event/data/value)[5]', 'varchar(max)') AS UserModeTime,
    EventData.value('(event/data/value)[6]', 'varchar(max)') AS KernelModeTime,
    EventData.value('(event/data/value)[7]', 'varchar(max)') AS PageFaults,
    EventData.value('(event/data/value)[8]', 'varchar(max)') AS WorkingSetDelta,
    EventData.value('(event/data/value)[9]', 'varchar(max)') AS MemoryUtilization,
    EventData.value('(event/data/value)[10]', 'varchar(max)') AS CallStack,
    EventData
    INTO SH_SchdMon_SysHealth_RB
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'scheduler_monitor_system_health_ring_buffer_recorded'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_SchdMon_SysHealth_RB
        INSERT INTO SH_SchdMon_SysHealth_RB
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'varchar(max)') AS ProcessUtilization,
        EventData.value('(event/data/value)[4]', 'varchar(max)') AS SystemIdle,
        EventData.value('(event/data/value)[5]', 'varchar(max)') AS UserModeTime,
        EventData.value('(event/data/value)[6]', 'varchar(max)') AS KernelModeTime,
        EventData.value('(event/data/value)[7]', 'varchar(max)') AS PageFaults,
        EventData.value('(event/data/value)[8]', 'varchar(max)') AS WorkingSetDelta,
        EventData.value('(event/data/value)[9]', 'varchar(max)') AS MemoryUtilization,
        EventData.value('(event/data/value)[10]', 'varchar(max)') AS CallStack,
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'scheduler_monitor_system_health_ring_buffer_recorded'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--populate table SH_wait_info_ext to process wait_info_external events
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[1]', 'varchar(max)') AS WaitTypeVal,
    EventData.value('(event/data/text)[1]', 'varchar(max)') AS WaitTypeText,
    EventData.value('(event/data/value)[2]', 'varchar(max)') AS OpCodeVal,
    EventData.value('(event/data/text)[2]', 'varchar(max)') AS OpCodeText,
    EventData.value('(event/data/value)[3]', 'varchar(max)') AS Duration,
    EventData.value('(event/action/value)[2]', 'varchar(max)') AS SessionID,
    EventData.value('(event/action/value)[3]', 'varchar(max)') AS SQLText,
    EventData.value('(event/action/value)[1]', 'varchar(max)') AS CallStack,
    EventData
    INTO SH_wait_info_ext
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'wait_info_external'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_wait_info_ext
        INSERT INTO SH_wait_info_ext
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[1]', 'varchar(max)') AS WaitTypeVal,
        EventData.value('(event/data/text)[1]', 'varchar(max)') AS WaitTypeText,
        EventData.value('(event/data/value)[2]', 'varchar(max)') AS OpCodeVal,
        EventData.value('(event/data/text)[2]', 'varchar(max)') AS OpCodeText,
        EventData.value('(event/data/value)[3]', 'varchar(max)') AS Duration,
        EventData.value('(event/action/value)[2]', 'varchar(max)') AS SessionID,
        EventData.value('(event/action/value)[3]', 'varchar(max)') AS SQLText,
        EventData.value('(event/action/value)[1]', 'varchar(max)') AS CallStack,
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'wait_info_external'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--populate table SH_sp_svr_diag_system to process sp_server_diagnostics_component_result for SYSTEM events
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/text)[1]', 'varchar(max)') AS SubSystem,
    EventData.value('(event/data/text)[2]', 'varchar(max)') AS State,
    EventData.value('(event/data/value/system/@spinlockBackoffs)[1]', 'varchar(max)') AS spinlockBackoffs,
    EventData.value('(event/data/value/system/@sickSpinlockType)[1]', 'varchar(max)') AS sickSpinlockType,
    EventData.value('(event/data/value/system/@sickSpinlockTypeAfterAv)[1]', 'varchar(max)') AS sickSpinlockTypeAfterAv,
    EventData.value('(event/data/value/system/@latchWarnings)[1]', 'int') AS latchWarnings,
    EventData.value('(event/data/value/system/@isAccessViolationOccurred)[1]', 'int') AS isAccessViolationOccurred,
    EventData.value('(event/data/value/system/@writeAccessViolationCount)[1]', 'int') AS writeAccessViolationCount,
    EventData.value('(event/data/value/system/@totalDumpRequests)[1]', 'int') AS totalDumpRequests,
    EventData.value('(event/data/value/system/@intervalDumpRequests)[1]', 'int') AS intervalDumpRequests,
    EventData.value('(event/data/value/system/@pageFaults)[1]', 'int') AS pageFaults,
    EventData.value('(event/data/value/system/@systemCpuUtilization)[1]', 'int') AS systemCpuUtilization,
    EventData.value('(event/data/value/system/@sqlCpuUtilization)[1]', 'int') AS sqlCpuUtilization,
    EventData.value('(event/data/value/system/@BadPagesDetected)[1]', 'int') AS BadPagesDetected,
    EventData.value('(event/data/value/system/@BadPagesFixed)[1]', 'int') AS BadPagesFixed,
    EventData.value('(event/data/value/system/@LastBadPageAddress)[1]', 'varchar(max)') AS LastBadPageAddress,
    EventData.value('(event/data/value/system/@nonYieldingTasksReported)[1]', 'int') AS nonYieldingTasksReported,
    EventData
    INTO SH_sp_svr_diag_system
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'sp_server_diagnostics_component_result'
        and EventData.value('(event/data/text)[1]', 'varchar(max)') = 'SYSTEM'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_sp_svr_diag_system
        INSERT INTO SH_sp_svr_diag_system
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/text)[1]', 'varchar(max)') AS SubSystem,
        EventData.value('(event/data/text)[2]', 'varchar(max)') AS State,
        EventData.value('(event/data/value/system/@spinlockBackoffs)[1]', 'varchar(max)') AS spinlockBackoffs,
        EventData.value('(event/data/value/system/@sickSpinlockType)[1]', 'varchar(max)') AS sickSpinlockType,
        EventData.value('(event/data/value/system/@sickSpinlockTypeAfterAv)[1]', 'varchar(max)') AS sickSpinlockTypeAfterAv,
        EventData.value('(event/data/value/system/@latchWarnings)[1]', 'int') AS latchWarnings,
        EventData.value('(event/data/value/system/@isAccessViolationOccurred)[1]', 'int') AS isAccessViolationOccurred,
        EventData.value('(event/data/value/system/@writeAccessViolationCount)[1]', 'int') AS writeAccessViolationCount,
        EventData.value('(event/data/value/system/@totalDumpRequests)[1]', 'int') AS totalDumpRequests,
        EventData.value('(event/data/value/system/@intervalDumpRequests)[1]', 'int') AS intervalDumpRequests,
        EventData.value('(event/data/value/system/@pageFaults)[1]', 'int') AS pageFaults,
        EventData.value('(event/data/value/system/@systemCpuUtilization)[1]', 'int') AS systemCpuUtilization,
        EventData.value('(event/data/value/system/@sqlCpuUtilization)[1]', 'int') AS sqlCpuUtilization,
        EventData.value('(event/data/value/system/@BadPagesDetected)[1]', 'int') AS BadPagesDetected,
        EventData.value('(event/data/value/system/@BadPagesFixed)[1]', 'int') AS BadPagesFixed,
        EventData.value('(event/data/value/system/@LastBadPageAddress)[1]', 'varchar(max)') AS LastBadPageAddress,
        EventData.value('(event/data/value/system/@nonYieldingTasksReported)[1]', 'int') AS nonYieldingTasksReported,
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'sp_server_diagnostics_component_result'
            and EventData.value('(event/data/text)[1]', 'varchar(max)') = 'SYSTEM'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--populate table SH_sp_svr_diag_resource to process sp_server_diagnostics_component_result for RESOURCE events
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/text)[1]', 'varchar(max)') AS SubSystem,
    EventData.value('(event/data/text)[2]', 'varchar(max)') AS State,
    EventData.value('(event/data/value/resource/@lastNotification)[1]', 'varchar(max)') AS lastNotification,
    EventData.value('(event/data/value/resource/@outOfMemoryExceptions)[1]', 'int') AS outOfMemoryExceptions,
    EventData.value('(event/data/value/resource/@isAnyPoolOutOfMemory)[1]', 'int') AS isAnyPoolOutOfMemory,
    EventData.value('(event/data/value/resource/@processOutOfMemoryPeriod)[1]', 'int') AS processOutOfMemoryPeriod,
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[1]', 'bigint') AS [AvailPhysMem],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[2]', 'bigint') AS [AvailVirtMem],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[3]', 'bigint') AS [AvailPagingFile],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[4]', 'bigint') AS [WorkingSet],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[5]', 'bigint') AS [%CommittedMemInWS],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[6]', 'bigint') AS [PageFaults],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[7]', 'int') AS [SysPhysMemHigh],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[8]', 'int') AS [SysPhysMemLow],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[9]', 'int') AS [ProcPhysMemLow],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[10]', 'int') AS [ProcVirtMemLow],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[11]', 'bigint') AS [VM Reserved],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[12]', 'bigint') AS [VM Committed],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[13]', 'bigint') AS [LckdPagesAllocated],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[14]', 'bigint') AS [LargePagesAllocated],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[15]', 'bigint') AS [Emergency Memory],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[16]', 'bigint') AS [Emergency Memory In Use],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[17]', 'bigint') AS [Target Committed],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[18]', 'bigint') AS [Current Committed],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[19]', 'bigint') AS [Pages Allocated],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[20]', 'bigint') AS [Pages Reserved],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[21]', 'bigint') AS [Pages Free],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[22]', 'bigint') AS [Pages In Use],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[23]', 'bigint') AS [Page Alloc Potential],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[24]', 'bigint') AS [NUMA Growth Phase],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[25]', 'bigint') AS [Last OOM Factor],
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[26]', 'bigint') AS [Last OS Error],
    EventData
    INTO SH_sp_svr_diag_resource
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'sp_server_diagnostics_component_result'
        and EventData.value('(event/data/text)[1]', 'varchar(max)') = 'RESOURCE'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_sp_svr_diag_resource
        INSERT INTO SH_sp_svr_diag_resource
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/text)[1]', 'varchar(max)') AS SubSystem,
        EventData.value('(event/data/text)[2]', 'varchar(max)') AS State,
        EventData.value('(event/data/value/resource/@lastNotification)[1]', 'varchar(max)') AS lastNotification,
        EventData.value('(event/data/value/resource/@outOfMemoryExceptions)[1]', 'int') AS outOfMemoryExceptions,
        EventData.value('(event/data/value/resource/@isAnyPoolOutOfMemory)[1]', 'int') AS isAnyPoolOutOfMemory,
        EventData.value('(event/data/value/resource/@processOutOfMemoryPeriod)[1]', 'int') AS processOutOfMemoryPeriod,
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[1]', 'bigint') AS [AvailPhysMem],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[2]', 'bigint') AS [AvailVirtMem],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[3]', 'bigint') AS [AvailPagingFile],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[4]', 'bigint') AS [WorkingSet],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[5]', 'bigint') AS [%CommittedMemInWS],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[6]', 'bigint') AS [PageFaults],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[7]', 'int') AS [SysPhysMemHigh],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[8]', 'int') AS [SysPhysMemLow],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[9]', 'int') AS [ProcPhysMemLow],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[10]', 'int') AS [ProcVirtMemLow],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[11]', 'bigint') AS [VM Reserved],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[12]', 'bigint') AS [VM Committed],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[13]', 'bigint') AS [LckdPagesAllocated],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[14]', 'bigint') AS [LargePagesAllocated],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[15]', 'bigint') AS [Emergency Memory],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[16]', 'bigint') AS [Emergency Memory In Use],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[17]', 'bigint') AS [Target Committed],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[18]', 'bigint') AS [Current Committed],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[19]', 'bigint') AS [Pages Allocated],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[20]', 'bigint') AS [Pages Reserved],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[21]', 'bigint') AS [Pages Free],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[22]', 'bigint') AS [Pages In Use],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[23]', 'bigint') AS [Page Alloc Potential],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[24]', 'bigint') AS [NUMA Growth Phase],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[25]', 'bigint') AS [Last OOM Factor],
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[26]', 'bigint') AS [Last OS Error],
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'sp_server_diagnostics_component_result'
            and EventData.value('(event/data/text)[1]', 'varchar(max)') = 'RESOURCE'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--populate table SH_sp_svr_diag_IO to process sp_server_diagnostics_component_result for IO subsystem
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/text)[1]', 'varchar(max)') AS SubSystem,
    EventData.value('(event/data/text)[2]', 'varchar(max)') AS State,
    EventData.value('(event/data/value/ioSubsystem/@ioLatchTimeouts)[1]', 'int') AS ioLatchTimeouts,
    EventData.value('(event/data/value/ioSubsystem/@intervalLongIos)[1]', 'int') AS intervalLongIos,
    EventData.value('(event/data/value/ioSubsystem/@totalLongIos)[1]', 'int') AS totalLongIos,
    EventData.query('event/data/value/ioSubsystem/longestPendingRequests') AS LongestPendingRequests,
    EventData
    INTO SH_sp_svr_diag_IO
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'sp_server_diagnostics_component_result'
        and EventData.value('(event/data/text)[1]', 'varchar(max)') = 'IO_SUBSYSTEM'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_sp_svr_diag_IO
        INSERT INTO SH_sp_svr_diag_IO
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/text)[1]', 'varchar(max)') AS SubSystem,
        EventData.value('(event/data/text)[2]', 'varchar(max)') AS State,
        EventData.value('(event/data/value/ioSubsystem/@ioLatchTimeouts)[1]', 'int') AS ioLatchTimeouts,
        EventData.value('(event/data/value/ioSubsystem/@intervalLongIos)[1]', 'int') AS intervalLongIos,
        EventData.value('(event/data/value/ioSubsystem/@totalLongIos)[1]', 'int') AS totalLongIos,
        EventData.query('event/data/value/ioSubsystem/longestPendingRequests') AS LongestPendingRequests,
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'sp_server_diagnostics_component_result'
            and EventData.value('(event/data/text)[1]', 'varchar(max)') = 'IO_SUBSYSTEM'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--populate table SH_sp_svr_diag_query to process sp_server_diagnostics_component_result for query processor
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/text)[1]', 'varchar(max)') AS SubSystem,
    EventData.value('(event/data/text)[2]', 'varchar(max)') AS State,
    EventData.value('(event/data/value/queryProcessing/@maxWorkers)[1]', 'int') AS maxWorkers,
    EventData.value('(event/data/value/queryProcessing/@workersCreated)[1]', 'int') AS workersCreated,
    EventData.value('(event/data/value/queryProcessing/@workersIdle)[1]', 'int') AS workersIdle,
    EventData.value('(event/data/value/queryProcessing/@tasksCompletedWithinInterval)[1]', 'int') AS tasksCompletedWithinInterval,
    EventData.value('(event/data/value/queryProcessing/@pendingTasks)[1]', 'int') AS pendingTasks,
    EventData.value('(event/data/value/queryProcessing/@oldestPendingTaskWaitingTime)[1]', 'int') AS oldestPendingTaskWaitingTime,
    EventData.value('(event/data/value/queryProcessing/@hasUnresolvableDeadlockOccurred)[1]', 'int') AS hasUnresolvableDeadlockOccurred,
    EventData.value('(event/data/value/queryProcessing/@hasDeadlockedSchedulersOccurred)[1]', 'int') AS hasDeadlockedSchedulersOccurred,
    EventData.value('(event/data/value/queryProcessing/@trackingNonYieldingScheduler)[1]', 'varchar(max)') AS trackingNonYieldingScheduler,
    EventData.value('(event/data/value/queryProcessing/topWaits/nonPreemptive/byCount/wait/@waitType)[1]', 'varchar(max)') AS topNonPreemptWaitByCount,
    EventData.value('(event/data/value/queryProcessing/topWaits/nonPreemptive/byDuration/wait/@waitType)[1]', 'varchar(max)') AS topNonPreemptWaitByDuration,
    EventData.value('(event/data/value/queryProcessing/topWaits/preemptive/byCount/wait/@waitType)[1]', 'varchar(max)') AS topPreemptWaitByCount,
    EventData.value('(event/data/value/queryProcessing/topWaits/preemptive/byDuration/wait/@waitType)[1]', 'varchar(max)') AS topPreemptWaitByDuration,
    EventData.query('/event/data/value/queryProcessing/topWaits') AS topWaits,
    EventData.query('/event/data/value/queryProcessing/cpuIntensiveRequests') AS cpuIntensiveRequests,
    EventData
    INTO SH_sp_svr_diag_query
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'sp_server_diagnostics_component_result'
        and EventData.value('(event/data/text)[1]', 'varchar(max)') = 'QUERY_PROCESSING'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_sp_svr_diag_query
        INSERT INTO SH_sp_svr_diag_query
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/text)[1]', 'varchar(max)') AS SubSystem,
        EventData.value('(event/data/text)[2]', 'varchar(max)') AS State,
        EventData.value('(event/data/value/queryProcessing/@maxWorkers)[1]', 'int') AS maxWorkers,
        EventData.value('(event/data/value/queryProcessing/@workersCreated)[1]', 'int') AS workersCreated,
        EventData.value('(event/data/value/queryProcessing/@workersIdle)[1]', 'int') AS workersIdle,
        EventData.value('(event/data/value/queryProcessing/@tasksCompletedWithinInterval)[1]', 'int') AS tasksCompletedWithinInterval,
        EventData.value('(event/data/value/queryProcessing/@pendingTasks)[1]', 'int') AS pendingTasks,
        EventData.value('(event/data/value/queryProcessing/@oldestPendingTaskWaitingTime)[1]', 'int') AS oldestPendingTaskWaitingTime,
        EventData.value('(event/data/value/queryProcessing/@hasUnresolvableDeadlockOccurred)[1]', 'int') AS hasUnresolvableDeadlockOccurred,
        EventData.value('(event/data/value/queryProcessing/@hasDeadlockedSchedulersOccurred)[1]', 'int') AS hasDeadlockedSchedulersOccurred,
        EventData.value('(event/data/value/queryProcessing/@trackingNonYieldingScheduler)[1]', 'varchar(max)') AS trackingNonYieldingScheduler,
        EventData.value('(event/data/value/queryProcessing/topWaits/nonPreemptive/byCount/wait/@waitType)[1]', 'varchar(max)') AS topNonPreemptWaitByCount,
        EventData.value('(event/data/value/queryProcessing/topWaits/nonPreemptive/byDuration/wait/@waitType)[1]', 'varchar(max)') AS topNonPreemptWaitByDuration,
        EventData.value('(event/data/value/queryProcessing/topWaits/preemptive/byCount/wait/@waitType)[1]', 'varchar(max)') AS topPreemptWaitByCount,
        EventData.value('(event/data/value/queryProcessing/topWaits/preemptive/byDuration/wait/@waitType)[1]', 'varchar(max)') AS topPreemptWaitByDuration,
        EventData.query('/event/data/value/queryProcessing/topWaits') AS topWaits,
        EventData.query('/event/data/value/queryProcessing/cpuIntensiveRequests') AS cpuIntensiveRequests,
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'sp_server_diagnostics_component_result'
            and EventData.value('(event/data/text)[1]', 'varchar(max)') = 'QUERY_PROCESSING'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

-- populate table SH_connect_RB for connectivity_ring_buffer_recorded events
BEGIN TRY
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[3]', 'varchar(max)') AS TypeVal,
    EventData.value('(event/data/text)[1]', 'varchar(max)') AS TypeText,
    EventData.value('(event/data/text)[2]', 'varchar(max)') AS Source,
    EventData.value('(event/data/value)[5]', 'varchar(max)') AS Session_ID,
    EventData.value('(event/data/value)[6]', 'varchar(max)') AS OS_Error,
    EventData.value('(event/data/value)[7]', 'varchar(max)') AS SNI_error,
    EventData.value('(event/data/value)[8]', 'varchar(max)') AS SNI_consumer_error,
    EventData.value('(event/data/value)[9]', 'varchar(max)') AS SNI_provider,
    EventData.value('(event/data/value)[10]', 'varchar(max)') AS State,
    EventData.value('(event/data/value)[11]', 'varchar(max)') AS LocalPort,
    EventData.value('(event/data/value)[12]', 'varchar(max)') AS RemotePort,
    EventData.value('(event/data/value)[13]', 'varchar(max)') AS TDSInputBufError,
    EventData.value('(event/data/value)[14]', 'varchar(max)') AS TDSOutputBufError,
    EventData.value('(event/data/value)[15]', 'varchar(max)') AS TDSInputBufBytes,
    EventData.value('(event/data/value)[16]', 'varchar(max)') AS TDSFlags,
    EventData.value('(event/data/text)[3]', 'varchar(max)') AS TDSFlagsText,
    EventData.value('(event/data/value)[17]', 'varchar(max)') AS TotalLoginTimeMS,
    EventData.value('(event/data/value)[18]', 'varchar(max)') AS LoginTaskEnquedMS,
    EventData.value('(event/data/value)[19]', 'varchar(max)') AS NetworkWritesMS,
    EventData.value('(event/data/value)[20]', 'varchar(max)') AS NetworkReadsMS,
    EventData.value('(event/data/value)[21]', 'varchar(max)') AS SSLProcessingMS,
    EventData.value('(event/data/value)[22]', 'varchar(max)') AS SSPIProcessingMS,
    EventData.value('(event/data/value)[23]', 'varchar(max)') AS LoginTrig_ResGovProcessingMS,
    EventData.value('(event/data/value)[24]', 'varchar(max)') AS ConnectionID,
    EventData.value('(event/data/value)[25]', 'varchar(max)') AS ConnectionPeerID,
    EventData.value('(event/data/value)[26]', 'varchar(max)') AS LocalHost,
    EventData.value('(event/data/value)[27]', 'varchar(max)') AS RemoteHost,
    EventData.value('(event/data/value)[28]', 'varchar(max)') AS CallStack,
    EventData
    INTO SH_connect_RB
    FROM SystemHealth_XELData
    WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'connectivity_ring_buffer_recorded'
    ORDER BY TimeStampUTC;
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SH_connect_RB
        INSERT INTO SH_connect_RB
        SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'varchar(max)') AS TypeVal,
        EventData.value('(event/data/text)[1]', 'varchar(max)') AS TypeText,
        EventData.value('(event/data/text)[2]', 'varchar(max)') AS Source,
        EventData.value('(event/data/value)[5]', 'varchar(max)') AS Session_ID,
        EventData.value('(event/data/value)[6]', 'varchar(max)') AS OS_Error,
        EventData.value('(event/data/value)[7]', 'varchar(max)') AS SNI_error,
        EventData.value('(event/data/value)[8]', 'varchar(max)') AS SNI_consumer_error,
        EventData.value('(event/data/value)[9]', 'varchar(max)') AS SNI_provider,
        EventData.value('(event/data/value)[10]', 'varchar(max)') AS State,
        EventData.value('(event/data/value)[11]', 'varchar(max)') AS LocalPort,
        EventData.value('(event/data/value)[12]', 'varchar(max)') AS RemotePort,
        EventData.value('(event/data/value)[13]', 'varchar(max)') AS TDSInputBufError,
        EventData.value('(event/data/value)[14]', 'varchar(max)') AS TDSOutputBufError,
        EventData.value('(event/data/value)[15]', 'varchar(max)') AS TDSInputBufBytes,
        EventData.value('(event/data/value)[16]', 'varchar(max)') AS TDSFlags,
        EventData.value('(event/data/text)[3]', 'varchar(max)') AS TDSFlagsText,
        EventData.value('(event/data/value)[17]', 'varchar(max)') AS TotalLoginTimeMS,
        EventData.value('(event/data/value)[18]', 'varchar(max)') AS LoginTaskEnquedMS,
        EventData.value('(event/data/value)[19]', 'varchar(max)') AS NetworkWritesMS,
        EventData.value('(event/data/value)[20]', 'varchar(max)') AS NetworkReadsMS,
        EventData.value('(event/data/value)[21]', 'varchar(max)') AS SSLProcessingMS,
        EventData.value('(event/data/value)[22]', 'varchar(max)') AS SSPIProcessingMS,
        EventData.value('(event/data/value)[23]', 'varchar(max)') AS LoginTrig_ResGovProcessingMS,
        EventData.value('(event/data/value)[24]', 'varchar(max)') AS ConnectionID,
        EventData.value('(event/data/value)[25]', 'varchar(max)') AS ConnectionPeerID,
        EventData.value('(event/data/value)[26]', 'varchar(max)') AS LocalHost,
        EventData.value('(event/data/value)[27]', 'varchar(max)') AS RemoteHost,
        EventData.value('(event/data/value)[28]', 'varchar(max)') AS CallStack,
        EventData
        FROM SystemHealth_XELData
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'connectivity_ring_buffer_recorded'
        ORDER BY TimeStampUTC;
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

PRINT '=================================='
PRINT 'WAIT_INFO events'
PRINT '=================================='
SELECT TimeStampUTC,
    cast(WaitType as varchar(25)) as WaitType,
    cast(OpCode as char(6)) as OpCode,
    cast(duration as varchar(12)) As [Duration(ms)],
    cast(signal_duration as varchar(15)) As [Signal Duration(ms)]
--  ,cast(session_id as varchar(10)) AS SessionID
--  ,cast (SQLText as varchar(200)) AS SQLText
--  ,EventData
    FROM SH_wait_info ORDER BY TimeStampUTC

PRINT '=================================='
PRINT 'WAIT_INFO_EXTERNAL events'
PRINT '=================================='
SELECT TimeStampUTC,
    cast(WaitTypeText as varchar(40)) as WaitTypeText,
    cast(OpCodeText as char(6)) as OpCode,
    cast(duration as varchar(12)) As [Duration(ms)]
--  ,cast(session_id as varchar(10)) AS SessionID
--  ,cast (SQLText as varchar(200)) AS SQLText
--  ,cast (CallStatck as varchar(200)) as CallStack
--  ,EventData
    FROM SH_wait_info_ext ORDER BY TimeStampUTC


PRINT '=================================='
PRINT 'Error Reported events'
PRINT '=================================='
SELECT TimeStampUTC,
    cast(error_number as VARCHAR(11)) AS ErrorNumber, 
    cast(severity as VARCHAR(10)) AS Severity, 
    cast(state as VARCHAR(10)) AS State, 
    cast(user_defined as VARCHAR(10)) AS UserDefined,
    cast(category as VARCHAR(10)) AS Category,
    cast(destination as VARCHAR(10)) AS Destination,
    cast(is_intercepted as VARCHAR(15)) AS IsIntercepted,
    message, session_id, database_id, EventData
    FROM SH_error_reported ORDER BY TimeStampUTC


SELECT * FROM SH_SchdMon_Deadlock_RB  ORDER BY TimeStampUTC
SELECT * FROM SH_SchdMon_NonYield_RB  ORDER BY TimeStampUTC
SELECT * FROM SH_SchdMon_NonYield_RM_RB  ORDER BY TimeStampUTC
SELECT * FROM SH_SchdMon_SysHealth_RB ORDER BY TimeStampUTC
SELECT * FROM SH_sp_svr_diag_system ORDER BY TimeStampUTC
SELECT * FROM SH_sp_svr_diag_resource ORDER BY TimeStampUTC
SELECT * FROM SH_sp_svr_diag_IO ORDER BY TimeStampUTC
SELECT * FROM SH_sp_svr_diag_query ORDER BY TimeStampUTC
SELECT * FROM SH_connect_RB ORDER BY TimeStampUTC
SELECT * FROM SH_security_error_ring_buffer_recorded ORDER BY TimeStampUTC
