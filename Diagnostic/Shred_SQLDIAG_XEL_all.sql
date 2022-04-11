/*=====================================================================
  AUTHOR:   Trayce Jordan (trayce@jordanhome.net)
  FILENAME: Shred_SQLDIAG_XEL_all.sql
  NOTES:

  use the CTRL-SHIFT-M macro substitution

  Database_name -- where the shredding script will store its data
                                okay for database to already to exist.
                                If the destination tables exist, they will be truncated and reloaded.

  XEL Folder path -- the path (relative to the SQL instance) of where the
                                *SQLDIAG_*.xel files are located  (failover cluster health XEL files)

  XEL File              -- filename (or wild card specification) of file to be shredded
                                by default the wildcard is "*SQLDIAG_*.xel" to shred
                                all failover cluster health XEL files in the specified folder.

                                NOTE:   it can take a long time to process all of the SQLDIAG  XEL files.
                                If the timeframe of interest is known and only a specific file is needed,
                                it is much quicker to specify a single file name rather than the wildcard.

TABLES OUTPUT
==============
dbo.SD_AGState                                  --AG state messages (including "lease valid"
dbo.SD_AGStatusChange                   --has events of AG state changes
dbo.SD_events_RB_Connectivity           -- connectivity ring buffer events
dbo.SD_events_RB_error_reported     -- error_reported ring buffer events
dbo.SD_events_RB_ResourceMon        -- resource_monitor_ring_buffer_recorded events
dbo.SD_events_RB_SchedMon           -- scheduler_monitor_ring_buffer_recorded  events
dbo.SD_events_RB_Security               --  security_error_ring_buffer_recorded  events
dbo.SD_InfoMessage          --info messages such as 
                                            "[hadrag] SQL Server component 'query_processing' health state has 
                                            been changed from 'clean' to 'warning' at 2015-02-10 22:04:26.300"

dbo.SD_IOSubsystem          --component health "IO Subsystem" data
dbo.SD_misc                     --should be empty unless there is unshredded data not processed
dbo.SD_query                        --contains component health "query" data
dbo.SD_resource                 --contains component health "resource" data
dbo.SD_System                   --contains component health "system" data
dbo.SQLDIAG_XELData     --Raw imput data from the XEL files

CHANGE HISTORY:
---------------------------
2016/10/11
		Changed secondary XML index to "property"  type fromm "path"
2015/08/12:
        Changed "object_name" to be varchar(25) in individual tables
        Added query for "info_message" to show non health info events

2015/07/28:
        Added support to shred RingBuffer information.   Table names prefixed:  dbo.SD_events_RB*
                (because the ring buffer events dump everything in RingBuffers at the time, there
                are lots of duplicates.   Only a distinct list of RB events are output - with the timestamp
                from the RingBuffer itself, not the timestamp of the XEL event.)

        Added support to shred AG State information.  Table name:   dbo.SD_AGState
        Added support fo shred AG status change information.  Table name:  dbo.SD_AGStatusChange.
        Added support to shred  "info messages".   Table name:  dbo.SD_InfoMessage
        Fixed bug in dbo.SD_Resource -- results are now populated instead of NULLs.
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
DECLARE @XELFile VARCHAR(max) = @XELPath + '<XELFile, varchar(max), *SQLDIAG_*.xel>'

--create table, indexes and views
BEGIN TRY
CREATE TABLE SQLDIAG_XELData
    (ID INT IDENTITY PRIMARY KEY CLUSTERED,
    object_name varchar(max),
    EventData XML,
    file_name varchar(max),
    file_offset bigint);
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SQLDIAG_XELData
        DROP INDEX sXML ON SQLDIAG_XELData
        DROP INDEX pXML ON SQLDIAG_XELData
    END ELSE 
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH


--read from the files into the table
INSERT INTO SQLDIAG_XELData
SELECT object_name, cast(event_data as XML) AS EventData,
  file_name, File_Offset
  FROM sys.fn_xe_file_target_read_file(
  @XELFile, NULL, null, null);

--create indexes
CREATE PRIMARY XML INDEX pXML ON SQLDIAG_XELData(EventData);
CREATE XML INDEX sXML 
    ON SQLDIAG_XELData (EventData)
    USING XML INDEX pXML FOR PROPERTY ;

-- Create table for "SD_System" events
BEGIN TRY
    SELECT CAST(object_name as VARCHAR(15)) ObjectName,
    EventData.value('(event/data/value)[5]', 'varchar(max)') AS Component,
    EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[3]', 'datetime') AS CreationTime,
    EventData.value('(event/data/value)[6]', 'varchar(max)') AS State_Desc,
    EventData.value('(event/data/value/system/@spinlockBackoffs)[1]', 'varchar(max)') AS spinlockBackoffs,
    EventData.value('(event/data/value/system/@sickSpinlockType)[1]', 'varchar(max)') AS sickSpinlockType,
    EventData.value('(event/data/value/system/@sickSpinlockTypeAfterAv)[1]', 'varchar(max)') AS sickSpinlockTypeAfterAv,
    EventData.value('(event/data/value/system/@latchWarnings)[1]', 'int') AS latchWarnings,
    EventData.value('(event/data/value/system/@isAccessViolationOccurred)[1]', 'int') AS isAccessViolationOccurred,
    EventData.value('(event/data/value/system/@writeAccessViolationCount)[1]', 'int') AS writeAccessViolationCount,
    EventData.value('(event/data/value/system/@intervalDumpRequests)[1]', 'int') AS intervalDumpRequests,
    EventData.value('(event/data/value/system/@pageFaults)[1]', 'int') AS pageFaults,
    EventData.value('(event/data/value/system/@systemCpuUtilization)[1]', 'int') AS systemCpuUtilization,
    EventData.value('(event/data/value/system/@sqlCpuUtilization)[1]', 'int') AS sqlCpuUtilization,
    EventData.value('(event/data/value/system/@BadPagesDetected)[1]', 'int') AS BadPagesDetected,
    EventData.value('(event/data/value/system/@BadPagesFixed)[1]', 'int') AS BadPagesFixed,
    EventData.value('(event/data/value/system/@LastBadPageAddress)[1]', 'varchar(max)') AS LastBadPageAddress,
    EventData.value('(event/data/value/system/@nonYieldingTasksReported)[1]', 'int') AS nonYieldingTasksReported
    INTO SD_System
    FROM SQLDIAG_XELData
    WHERE EventData.value('(event/data/value)[5]', 'varchar(max)') = 'system';
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_System
        INSERT INTO SD_System
        SELECT CAST(object_name as VARCHAR(15)) ObjectName,
        EventData.value('(event/data/value)[5]', 'varchar(max)') AS Component,
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'datetime') AS CreationTime,
        EventData.value('(event/data/value)[6]', 'varchar(max)') AS State_Desc,
        EventData.value('(event/data/value/system/@spinlockBackoffs)[1]', 'varchar(max)') AS spinlockBackoffs,
        EventData.value('(event/data/value/system/@sickSpinlockType)[1]', 'varchar(max)') AS sickSpinlockType,
        EventData.value('(event/data/value/system/@sickSpinlockTypeAfterAv)[1]', 'varchar(max)') AS sickSpinlockTypeAfterAv,
        EventData.value('(event/data/value/system/@latchWarnings)[1]', 'int') AS latchWarnings,
        EventData.value('(event/data/value/system/@isAccessViolationOccurred)[1]', 'int') AS isAccessViolationOccurred,
        EventData.value('(event/data/value/system/@writeAccessViolationCount)[1]', 'int') AS writeAccessViolationCount,
        EventData.value('(event/data/value/system/@intervalDumpRequests)[1]', 'int') AS intervalDumpRequests,
        EventData.value('(event/data/value/system/@pageFaults)[1]', 'int') AS pageFaults,
        EventData.value('(event/data/value/system/@systemCpuUtilization)[1]', 'int') AS systemCpuUtilization,
        EventData.value('(event/data/value/system/@sqlCpuUtilization)[1]', 'int') AS sqlCpuUtilization,
        EventData.value('(event/data/value/system/@BadPagesDetected)[1]', 'int') AS BadPagesDetected,
        EventData.value('(event/data/value/system/@BadPagesFixed)[1]', 'int') AS BadPagesFixed,
        EventData.value('(event/data/value/system/@LastBadPageAddress)[1]', 'varchar(max)') AS LastBadPageAddress,
        EventData.value('(event/data/value/system/@nonYieldingTasksReported)[1]', 'int') AS nonYieldingTasksReported
        FROM SQLDIAG_XELData
        WHERE EventData.value('(event/data/value)[5]', 'varchar(max)') = 'system';
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH


-- Create table for "SD_iosubsystem" events
BEGIN TRY
    SELECT CAST(object_name as VARCHAR(15)) ObjectName,
    EventData.value('(event/data/value)[5]', 'varchar(max)') AS Component,
    EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[3]', 'datetime') AS CreationTime,
    EventData.value('(event/data/value)[6]', 'varchar(max)') AS State_Desc,
    EventData.value('(event/data/value/ioSubsystem/@ioLatchTimeouts)[1]', 'int') AS ioLatchTimeouts,
    EventData.value('(event/data/value/ioSubsystem/@intervalLongIos)[1]', 'int') AS intervalLongIos,
    EventData.value('(event/data/value/ioSubsystem/@totalLongIos)[1]', 'int') AS totalLongIos,
    EventData.value('(event/data/value/ioSubsystem/longestPendingRequests/pendingRequest/@duration)[1]', 'int') AS duration,
    EventData.value('(event/data/value/ioSubsystem/longestPendingRequests/pendingRequest/@filePath)[1]', 'varchar(max)') AS filePath
    INTO SD_iosubsystem
    FROM SQLDIAG_XELData
    WHERE EventData.value('(event/data/value)[5]', 'varchar(max)') = 'io_subsystem';
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_iosubsystem
        INSERT INTO SD_iosubsystem
        SELECT CAST(object_name as VARCHAR(15)) ObjectName,
        EventData.value('(event/data/value)[5]', 'varchar(max)') AS Component,
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'datetime') AS CreationTime,
        EventData.value('(event/data/value)[6]', 'varchar(max)') AS State_Desc,
        EventData.value('(event/data/value/ioSubsystem/@ioLatchTimeouts)[1]', 'int') AS ioLatchTimeouts,
        EventData.value('(event/data/value/ioSubsystem/@intervalLongIos)[1]', 'int') AS intervalLongIos,
        EventData.value('(event/data/value/ioSubsystem/@totalLongIos)[1]', 'int') AS totalLongIos,
        EventData.value('(event/data/value/ioSubsystem/longestPendingRequests/pendingRequest/@duration)[1]', 'int') AS duration,
        EventData.value('(event/data/value/ioSubsystem/longestPendingRequests/pendingRequest/@filePath)[1]', 'varchar(max)') AS filePath
        FROM SQLDIAG_XELData
        WHERE EventData.value('(event/data/value)[5]', 'varchar(max)') = 'io_subsystem';
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH


-- Create table for "SD_query" events
BEGIN TRY
    SELECT CAST(object_name as VARCHAR(15)) ObjectName,
    EventData.value('(event/data/value)[5]', 'varchar(max)') AS Component,
    EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[3]', 'datetime') AS CreationTime,
    EventData.value('(event/data/value)[6]', 'varchar(max)') AS State_Desc,
    EventData.value('(event/data/value/queryProcessing/@maxWorkers)[1]', 'int') AS maxWorkers,
    EventData.value('(event/data/value/queryProcessing/@workersCreated)[1]', 'int') AS workersCreated,
    EventData.value('(event/data/value/queryProcessing/@workersIdle)[1]', 'int') AS workersIdle,
    EventData.value('(event/data/value/queryProcessing/@trackingNonYieldingScheduler)[1]', 'varchar(max)') AS trackingNonYieldingScheduler,
    EventData.value('(event/data/value/queryProcessing/@tasksCompletedWithinInterval)[1]', 'int') AS tasksCompletedWithinInterval,
    EventData.value('(event/data/value/queryProcessing/@pendingTasks)[1]', 'int') AS pendingTasks,
    EventData.value('(event/data/value/queryProcessing/@oldestPendingTaskWaitingTime)[1]', 'int') AS oldestPendingTaskWaitingTime,
    EventData.value('(event/data/value/queryProcessing/@hasUnresolvableDeadlockOccurred)[1]', 'int') AS hasUnresolvableDeadlockOccurred,
    EventData.value('(event/data/value/queryProcessing/@hasDeadlockedSchedulersOccurred)[1]', 'int') AS hasDeadlockedSchedulersOccurred,
    EventData.value('(event/data/value/queryProcessing/topWaits/nonPreemptive/byCount/wait/@waitType)[1]', 'varchar(max)') AS topNonPreemptWaitByCount,
    EventData.value('(event/data/value/queryProcessing/topWaits/nonPreemptive/byDuration/wait/@waitType)[1]', 'varchar(max)') AS topNonPreemptWaitByDuration,
    EventData.value('(event/data/value/queryProcessing/topWaits/preemptive/byCount/wait/@waitType)[1]', 'varchar(max)') AS topPreemptWaitByCount,
    EventData.value('(event/data/value/queryProcessing/topWaits/preemptive/byDuration/wait/@waitType)[1]', 'varchar(max)') AS topPreemptWaitByDuration,
    EventData.query('/event/data/value/queryProcessing/topWaits') AS topWaits,
    EventData.query('/event/data/value/queryProcessing/cpuIntensiveRequests') AS cpuIntensiveRequests
    INTO SD_query
    FROM SQLDIAG_XELData
    WHERE EventData.value('(event/data/value)[5]', 'varchar(max)') = 'query_processing';
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_query
        INSERT INTO SD_query
        SELECT CAST(object_name as VARCHAR(15)) ObjectName,
        EventData.value('(event/data/value)[5]', 'varchar(max)') AS Component,
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'datetime') AS CreationTime,
        EventData.value('(event/data/value)[6]', 'varchar(max)') AS State_Desc,
        EventData.value('(event/data/value/queryProcessing/@maxWorkers)[1]', 'int') AS maxWorkers,
        EventData.value('(event/data/value/queryProcessing/@workersCreated)[1]', 'int') AS workersCreated,
        EventData.value('(event/data/value/queryProcessing/@workersIdle)[1]', 'int') AS workersIdle,
        EventData.value('(event/data/value/queryProcessing/@trackingNonYieldingScheduler)[1]', 'varchar(max)') AS trackingNonYieldingScheduler,
        EventData.value('(event/data/value/queryProcessing/@tasksCompletedWithinInterval)[1]', 'int') AS tasksCompletedWithinInterval,
        EventData.value('(event/data/value/queryProcessing/@pendingTasks)[1]', 'int') AS pendingTasks,
        EventData.value('(event/data/value/queryProcessing/@oldestPendingTaskWaitingTime)[1]', 'int') AS oldestPendingTaskWaitingTime,
        EventData.value('(event/data/value/queryProcessing/@hasUnresolvableDeadlockOccurred)[1]', 'int') AS hasUnresolvableDeadlockOccurred,
        EventData.value('(event/data/value/queryProcessing/@hasDeadlockedSchedulersOccurred)[1]', 'int') AS hasDeadlockedSchedulersOccurred,
        EventData.value('(event/data/value/queryProcessing/topWaits/nonPreemptive/byCount/wait/@waitType)[1]', 'varchar(max)') AS topNonPreemptWaitByCount,
        EventData.value('(event/data/value/queryProcessing/topWaits/nonPreemptive/byDuration/wait/@waitType)[1]', 'varchar(max)') AS topNonPreemptWaitByDuration,
        EventData.value('(event/data/value/queryProcessing/topWaits/preemptive/byCount/wait/@waitType)[1]', 'varchar(max)') AS topPreemptWaitByCount,
        EventData.value('(event/data/value/queryProcessing/topWaits/preemptive/byDuration/wait/@waitType)[1]', 'varchar(max)') AS topPreemptWaitByDuration,
        EventData.query('/event/data/value/queryProcessing/topWaits') AS topWaits,
        EventData.query('/event/data/value/queryProcessing/cpuIntensiveRequests') AS cpuIntensiveRequests
        FROM SQLDIAG_XELData
        WHERE EventData.value('(event/data/value)[5]', 'varchar(max)') = 'query_processing';
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

-- Create table for "SD_resource" events
BEGIN TRY
    SELECT CAST(object_name as VARCHAR(15)) ObjectName,
    EventData.value('(event/data/value)[5]', 'varchar(max)') AS Component,
    EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[3]', 'datetime') AS CreationTime,
    EventData.value('(event/data/value)[6]', 'varchar(max)') AS State_Desc,
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
    EventData.value('(event/data/value/resource/memoryReport/entry/@value)[26]', 'bigint') AS [Last OS Error]
    INTO SD_resource
    FROM SQLDIAG_XELData
    WHERE EventData.value('(event/data/value)[5]', 'varchar(max)') = 'resource';
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_resource
        INSERT INTO SD_resource
        SELECT CAST(object_name as VARCHAR(15)) ObjectName,
        EventData.value('(event/data/value)[5]', 'varchar(max)') AS Component,
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'datetime') AS CreationTime,
        EventData.value('(event/data/value)[6]', 'varchar(max)') AS State_Desc,
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
        EventData.value('(event/data/value/resource/memoryReport/entry/@value)[26]', 'bigint') AS [Last OS Error]
        FROM SQLDIAG_XELData
        WHERE EventData.value('(event/data/value)[5]', 'varchar(max)') = 'resource';
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

--Create table for AG Status change
BEGIN TRY
        SELECT CAST(object_name as VARCHAR(15)) ObjectName,
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[5]', 'varchar(25)') AS InstanceName,
        EventData.value('(event/data/value)[4]', 'varchar(25)') AS AGName,
        EventData.value('(event/data/value)[1]', 'varchar(11)') AS TargetState,
        EventData.value('(event/data/text)[1]', 'varchar(25)') AS TargetStateDesc,
        EventData.value('(event/data/value)[2]', 'varchar(21)') AS FailureConditionLevel,
        EventData.value('(event/data/text)[2]', 'varchar(25)') AS HealthState,
        EventData.value('(event/data/value)[3]', 'varchar(36)') AS AGClusterResourceID
        INTO SD_AGStatusChange
        FROM SQLDIAG_XELData
        WHERE object_name = 'availability_group_state_change'
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_AGStatusChange
        INSERT INTO SD_AGStatusChange
        SELECT CAST(object_name as VARCHAR(15)) ObjectName,
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[5]', 'varchar(25)') AS InstanceName,
        EventData.value('(event/data/value)[4]', 'varchar(25)') AS AGName,
        EventData.value('(event/data/value)[1]', 'varchar(11)') AS TargetState,
        EventData.value('(event/data/text)[1]', 'varchar(25)') AS TargetStateDesc,
        EventData.value('(event/data/value)[2]', 'varchar(21)') AS FailureConditionLevel,
        EventData.value('(event/data/text)[2]', 'varchar(25)') AS HealthState,
        EventData.value('(event/data/value)[3]', 'varchar(36)') AS AGClusterResourceID
        FROM SQLDIAG_XELData
        WHERE object_name = 'availability_group_state_change'
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

-- Create table for "info_message" events
BEGIN TRY
        SELECT CAST(object_name as VARCHAR(15)) ObjectName,
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'varchar(25)') AS NodeName,
        EventData.value('(event/data/value)[2]', 'varchar(25)') AS InstanceName,
        EventData.value('(event/data/value)[1]', 'varchar(max)') AS InfoMessage
        INTO SD_InfoMessage
        FROM SQLDIAG_XELData
        WHERE object_name = 'info_message'
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_InfoMessage
        INSERT INTO SD_InfoMessage
        SELECT CAST(object_name as VARCHAR(15)) ObjectName,
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'varchar(25)') AS NodeName,
        EventData.value('(event/data/value)[2]', 'varchar(25)') AS InstanceName,
        EventData.value('(event/data/value)[1]', 'varchar(max)') AS InfoMessage
        FROM SQLDIAG_XELData
        WHERE object_name = 'info_message'
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH


-- Create table for "SD_misc" events
BEGIN TRY
    SELECT CAST(object_name as VARCHAR(15)) ObjectName,
    EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[5]', 'varchar(max)') AS Component,
    EventData
    INTO SD_misc
    FROM SQLDIAG_XELData
    WHERE object_name =   'component_health_result' AND 
        EventData.value('(event/data/value)[5]', 'varchar(max)') 
            NOT IN ('resource', 'io_subsystem', 'system', 'query_processing', 'events')   AND
        EventData.value('(event/data/value)[4]', 'varchar(max)') <> 'alwaysOn:AvailabilityGroup';
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_misc
        INSERT INTO SD_misc
        SELECT CAST(object_name as VARCHAR(15)) ObjectName,
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[5]', 'varchar(max)') AS Component,
        EventData
        FROM SQLDIAG_XELData
        WHERE object_name =   'component_health_result' AND 
            EventData.value('(event/data/value)[5]', 'varchar(max)') 
                NOT IN ('resource', 'io_subsystem', 'system', 'query_processing', 'events')   AND
            EventData.value('(event/data/value)[4]', 'varchar(max)') <> 'alwaysOn:AvailabilityGroup';
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH;

-- Create table for "SD_events_RB_error_reported" events
BEGIN TRY
        WITH RBErrorReported(Node) AS (
            SELECT EventData.query('//*/RingBufferTarget/event[@name = ''error_reported'']') 
            FROM SQLDIAG_XELData
            WHERE object_name = 'component_health_result' AND
                EventData.exist('//*/RingBufferTarget/event[@name = ''error_reported'']') = 1
            ) --CTE:RBErrorReported
        SELECT DISTINCT
                Node.value('(/event/@timestamp)[1]', 'datetime') AS RBEventTimeStampUTC,
                Node.value('(event/data/value)[1]', 'varchar(11)') AS ErrorNumber,
                Node.value('(event/data/value)[2]', 'varchar(10)') AS Severity,
                Node.value('(event/data/value)[3]', 'varchar(10)') AS [State],
                Node.value('(event/data/value)[4]', 'varchar(10)') AS [UserDefined],
                Node.value('(event/data/value)[5]', 'varchar(10)') AS [Category],
                Node.value('(event/data/text)[5]', 'varchar(15)') AS [CategoryDesc],
                Node.value('(event/data/value)[6]', 'varchar(11)') AS [Destination],
                Node.value('(event/data/text)[6]', 'varchar(35)') AS [DestinationDesc],
                Node.value('(event/data/value)[7]', 'varchar(13)') AS [IsIntercepted],
                Node.value('(event/data/value)[8]', 'varchar(max)') AS [Message]
                INTO SD_events_RB_error_reported
                FROM RBErrorReported
                ORDER BY 1
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_events_RB_error_reported;
        WITH RBErrorReported(Node) AS (
            SELECT EventData.query('//*/RingBufferTarget/event[@name = ''error_reported'']') 
            FROM SQLDIAG_XELData
            WHERE object_name = 'component_health_result' AND
                EventData.exist('//*/RingBufferTarget/event[@name = ''error_reported'']') = 1
            ) --CTE:RBErrorReported
        INSERT INTO SD_events_RB_error_reported
        SELECT DISTINCT
                Node.value('(/event/@timestamp)[1]', 'datetime') AS RBEventTimeStampUTC,
                Node.value('(event/data/value)[1]', 'varchar(11)') AS ErrorNumber,
                Node.value('(event/data/value)[2]', 'varchar(10)') AS Severity,
                Node.value('(event/data/value)[3]', 'varchar(10)') AS [State],
                Node.value('(event/data/value)[4]', 'varchar(10)') AS [UserDefined],
                Node.value('(event/data/value)[5]', 'varchar(10)') AS [Category],
                Node.value('(event/data/text)[5]', 'varchar(15)') AS [CategoryDesc],
                Node.value('(event/data/value)[6]', 'varchar(11)') AS [Destination],
                Node.value('(event/data/text)[6]', 'varchar(35)') AS [DestinationDesc],
                Node.value('(event/data/value)[7]', 'varchar(13)') AS [IsIntercepted],
                Node.value('(event/data/value)[8]', 'varchar(max)') AS [Message]
                FROM RBErrorReported
                ORDER BY 1
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH


-- Create table for "SD_events_RB_schedmon" events
BEGIN TRY
        WITH RBSchedMon(Node) AS (
            SELECT EventData.query('//*/RingBufferTarget/event[@name = ''scheduler_monitor_system_health_ring_buffer_recorded'']') 
            FROM SQLDIAG_XELData
            WHERE object_name = 'component_health_result' AND
                EventData.exist('//*/RingBufferTarget/event[@name = ''scheduler_monitor_system_health_ring_buffer_recorded'']') = 1
            ) --CTE:RBSchedMon
        SELECT DISTINCT
                Node.value('(/event/@timestamp)[1]', 'datetime') AS RBEventTimeStampUTC,
                Node.value('(event/data/value)[1]', 'varchar(10)') AS ID,
                Node.value('(event/data/value)[2]', 'varchar(20)') AS [timestamp],
                Node.value('(event/data/value)[3]', 'varchar(19)') AS [process_utilization],
                Node.value('(event/data/value)[4]', 'varchar(11)') AS [system_idle],
                Node.value('(event/data/value)[5]', 'varchar(20)') AS [user_mode_time],
                Node.value('(event/data/value)[6]', 'varchar(20)') AS [kernel_mode_time],
                Node.value('(event/data/value)[7]', 'varchar(11)') AS [page_faults],
                Node.value('(event/data/value)[8]', 'varchar(20)') AS [working_set_delta],
                Node.value('(event/data/value)[9]', 'varchar(18)') AS [memory_utilization]
                INTO SD_events_RB_schedmon
                FROM RBSchedMon
                ORDER BY 1
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_events_RB_schedmon;
        WITH RBSchedMon(Node) AS (
            SELECT EventData.query('//*/RingBufferTarget/event[@name = ''scheduler_monitor_system_health_ring_buffer_recorded'']') 
            FROM SQLDIAG_XELData
            WHERE object_name = 'component_health_result' AND
                EventData.exist('//*/RingBufferTarget/event[@name = ''scheduler_monitor_system_health_ring_buffer_recorded'']') = 1
            ) --CTE:RBSchedMon
        INSERT INTO SD_events_RB_schedmon
        SELECT DISTINCT
                Node.value('(/event/@timestamp)[1]', 'datetime') AS RBEventTimeStampUTC,
                Node.value('(event/data/value)[1]', 'varchar(10)') AS ID,
                Node.value('(event/data/value)[2]', 'varchar(20)') AS [timestamp],
                Node.value('(event/data/value)[3]', 'varchar(19)') AS [process_utilization],
                Node.value('(event/data/value)[4]', 'varchar(11)') AS [system_idle],
                Node.value('(event/data/value)[5]', 'varchar(20)') AS [user_mode_time],
                Node.value('(event/data/value)[6]', 'varchar(20)') AS [kernel_mode_time],
                Node.value('(event/data/value)[7]', 'varchar(11)') AS [page_faults],
                Node.value('(event/data/value)[8]', 'varchar(20)') AS [working_set_delta],
                Node.value('(event/data/value)[9]', 'varchar(18)') AS [memory_utilization]
                FROM RBSchedMon
                ORDER BY 1
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

-- Create table for "resource_monitor_ring_buffer_recorded" events
BEGIN TRY
        WITH RBResourceMon(Node) AS (
            SELECT EventData.query('//*/RingBufferTarget/event[@name = ''resource_monitor_ring_buffer_recorded'']') 
            FROM SQLDIAG_XELData
            WHERE object_name = 'component_health_result' AND
                EventData.exist('//*/RingBufferTarget/event[@name = ''resource_monitor_ring_buffer_recorded'']') = 1
            ) --CTE:RBResourceMon
        SELECT DISTINCT
                Node.value('(/event/@timestamp)[1]', 'datetime') AS RBEventTimeStampUTC,
                Node.value('(event/data/value)[1]', 'varchar(10)') AS ID,
                Node.value('(event/data/value)[2]', 'varchar(20)') AS [timestamp],
                Node.value('(event/data/value)[22]', 'varchar(10)') AS [NodeID],
                Node.value('(event/data/value)[11]', 'varchar(10)') AS [memory_node_id],
                Node.value('(event/data/value)[3]', 'varchar(20)') AS [MemoryUtilizationPct],
                Node.value('(event/data/value)[4]', 'varchar(20)') AS [TotalPhysicalMemoryKB],
                Node.value('(event/data/value)[5]', 'varchar(20)') AS [AvailPhysicalMemoryKB],
                Node.value('(event/data/value)[6]', 'varchar(20)') AS [TotalPageFileKB],
                Node.value('(event/data/value)[7]', 'varchar(20)') AS [AvailPageFileKB],
                Node.value('(event/data/value)[8]', 'varchar(20)') AS [TotalVirtualAddressSpaceKB],
                Node.value('(event/data/value)[9]', 'varchar(20)') AS [AvailVirtualAddressSpaceKB],
                Node.value('(event/data/value)[10]', 'varchar(20)') AS [AvailExtndVirtualAddrSpaceKB],
                Node.value('(event/data/value)[12]', 'varchar(20)') AS [TargetKB],
                Node.value('(event/data/value)[13]', 'varchar(20)') AS [ReservedKB],
                Node.value('(event/data/value)[14]', 'varchar(20)') AS [CommittedKB],
                Node.value('(event/data/value)[15]', 'varchar(20)') AS [SharedCommittedKB],
                Node.value('(event/data/value)[16]', 'varchar(20)') AS [AWE_KB],
                Node.value('(event/data/value)[17]', 'varchar(20)') AS [Pages_KB],
                Node.value('(event/data/type/@name)[18]', 'varchar(20)') AS [NotificationType],
                Node.value('(event/data/value)[18]', 'varchar(20)') AS [NotificationValue],
                Node.value('(event/data/text)[1]', 'varchar(20)') AS [NotificationText],
                Node.value('(event/data/value)[19]', 'varchar(10)') AS [ProcessIndicators],
                Node.value('(event/data/value)[20]', 'varchar(10)') AS [SystemIndicators],
                Node.value('(event/data/value)[21]', 'varchar(10)') AS [PoolIndicators],
                Node.value('(event/data/value)[23]', 'varchar(10)') AS [ApplyLowPMValue],
                Node.value('(event/data/text)[2]', 'varchar(10)') AS [ApplyLowPMText],
                Node.value('(event/data/value)[24]', 'varchar(10)') AS [ApplyHighPMValue],
                Node.value('(event/data/text)[3]', 'varchar(10)') AS [ApplyHighPMText],
                Node.value('(event/data/value)[25]', 'varchar(10)') AS [RevertHighPMValue],
                Node.value('(event/data/text)[4]', 'varchar(10)') AS [RevertHighPMText]
                INTO SD_events_RB_ResourceMon
                FROM RBResourceMon
                ORDER BY 1
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_events_RB_ResourceMon;
        WITH RBResourceMon(Node) AS (
            SELECT EventData.query('//*/RingBufferTarget/event[@name = ''resource_monitor_ring_buffer_recorded'']') 
            FROM SQLDIAG_XELData
            WHERE object_name = 'component_health_result' AND
                EventData.exist('//*/RingBufferTarget/event[@name = ''resource_monitor_ring_buffer_recorded'']') = 1
            ) --CTE:RBResourceMon
        INSERT INTO SD_events_RB_ResourceMon
        SELECT DISTINCT
                Node.value('(/event/@timestamp)[1]', 'datetime') AS RBEventTimeStampUTC,
                Node.value('(event/data/value)[1]', 'varchar(10)') AS ID,
                Node.value('(event/data/value)[2]', 'varchar(20)') AS [timestamp],
                Node.value('(event/data/value)[22]', 'varchar(10)') AS [NodeID],
                Node.value('(event/data/value)[11]', 'varchar(10)') AS [memory_node_id],
                Node.value('(event/data/value)[3]', 'varchar(20)') AS [MemoryUtilizationPct],
                Node.value('(event/data/value)[4]', 'varchar(20)') AS [TotalPhysicalMemoryKB],
                Node.value('(event/data/value)[5]', 'varchar(20)') AS [AvailPhysicalMemoryKB],
                Node.value('(event/data/value)[6]', 'varchar(20)') AS [TotalPageFileKB],
                Node.value('(event/data/value)[7]', 'varchar(20)') AS [AvailPageFileKB],
                Node.value('(event/data/value)[8]', 'varchar(20)') AS [TotalVirtualAddressSpaceKB],
                Node.value('(event/data/value)[9]', 'varchar(20)') AS [AvailVirtualAddressSpaceKB],
                Node.value('(event/data/value)[10]', 'varchar(20)') AS [AvailExtndVirtualAddrSpaceKB],
                Node.value('(event/data/value)[12]', 'varchar(20)') AS [TargetKB],
                Node.value('(event/data/value)[13]', 'varchar(20)') AS [ReservedKB],
                Node.value('(event/data/value)[14]', 'varchar(20)') AS [CommittedKB],
                Node.value('(event/data/value)[15]', 'varchar(20)') AS [SharedCommittedKB],
                Node.value('(event/data/value)[16]', 'varchar(20)') AS [AWE_KB],
                Node.value('(event/data/value)[17]', 'varchar(20)') AS [Pages_KB],
                Node.value('(event/data/type/@name)[18]', 'varchar(20)') AS [NotificationType],
                Node.value('(event/data/value)[18]', 'varchar(20)') AS [NotificationValue],
                Node.value('(event/data/text)[1]', 'varchar(20)') AS [NotificationText],
                Node.value('(event/data/value)[19]', 'varchar(10)') AS [ProcessIndicators],
                Node.value('(event/data/value)[20]', 'varchar(10)') AS [SystemIndicators],
                Node.value('(event/data/value)[21]', 'varchar(10)') AS [PoolIndicators],
                Node.value('(event/data/value)[23]', 'varchar(10)') AS [ApplyLowPMValue],
                Node.value('(event/data/text)[2]', 'varchar(10)') AS [ApplyLowPMText],
                Node.value('(event/data/value)[24]', 'varchar(10)') AS [ApplyHighPMValue],
                Node.value('(event/data/text)[3]', 'varchar(10)') AS [ApplyHighPMText],
                Node.value('(event/data/value)[25]', 'varchar(10)') AS [RevertHighPMValue],
                Node.value('(event/data/text)[4]', 'varchar(10)') AS [RevertHighPMText]
                FROM RBResourceMon
                ORDER BY 1
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

-- Create table for "connectivity_ring_buffer_recorded" events
BEGIN TRY
        WITH RBConnectivity(Node) AS (
            SELECT EventData.query('//*/RingBufferTarget/event[@name = ''connectivity_ring_buffer_recorded'']') 
            FROM SQLDIAG_XELData
            WHERE object_name = 'component_health_result' AND
                EventData.exist('//*/RingBufferTarget/event[@name = ''connectivity_ring_buffer_recorded'']') = 1
            ) --CTE:RBConnectivity
        SELECT DISTINCT
                Node.value('(/event/@timestamp)[1]', 'datetime') AS RBEventTimeStampUTC,
                Node.value('(event/data/value)[1]', 'varchar(10)') AS ID,
                Node.value('(event/data/value)[2]', 'varchar(20)') AS [timestamp],
                Node.value('(event/data/value)[3]', 'varchar(10)') AS [ConnectivityRecordType],
                Node.value('(event/data/text)[1]', 'varchar(20)') AS [ConnectivityRecordTypeDesc],
                Node.value('(event/data/value)[4]', 'varchar(20)') AS [Source],
                Node.value('(event/data/text)[2]', 'varchar(20)') AS [SourceType],
                Node.value('(event/data/value)[5]', 'varchar(10)') AS [SessionID],
                Node.value('(event/data/value)[6]', 'varchar(10)') AS [OSError],
                Node.value('(event/data/value)[7]', 'varchar(10)') AS [SNIError],
                Node.value('(event/data/value)[8]', 'varchar(10)') AS [SNIConsumerError],
                Node.value('(event/data/value)[9]', 'varchar(10)') AS [SNIProvider],
                Node.value('(event/data/value)[10]', 'varchar(10)') AS [State],
                Node.value('(event/data/value)[11]', 'varchar(10)') AS [LocalPort],
                Node.value('(event/data/value)[12]', 'varchar(10)') AS [RemotePort],
                Node.value('(event/data/value)[13]', 'varchar(10)') AS [TDSInputBufferError],
                Node.value('(event/data/value)[14]', 'varchar(10)') AS [TDSOutputBufferError],
                Node.value('(event/data/value)[15]', 'varchar(10)') AS [TDSInputBufferBYtes],
                Node.value('(event/data/value)[16]', 'varchar(10)') AS [TDSFlag],
                Node.value('(event/data/text)[3]', 'varchar(30)') AS [TDSFlagDesc],
                Node.value('(event/data/value)[17]', 'varchar(10)') AS [total_login_time_ms],
                Node.value('(event/data/value)[18]', 'varchar(10)') AS [login_task_enqueued_ms],
                Node.value('(event/data/value)[19]', 'varchar(10)') AS [network_writes_ms],
                Node.value('(event/data/value)[20]', 'varchar(10)') AS [network_reads_ms],
                Node.value('(event/data/value)[21]', 'varchar(10)') AS [ssl_processing_ms],
                Node.value('(event/data/value)[22]', 'varchar(10)') AS [sspi_processing_ms],
                Node.value('(event/data/value)[23]', 'varchar(10)') AS [login_trigger_and_resource_governor_processing_ms],
                Node.value('(event/data/value)[24]', 'varchar(36)') AS [connection_id],
                Node.value('(event/data/value)[25]', 'varchar(36)') AS [connection_peer_id],
                Node.value('(event/data/value)[26]', 'varchar(15)') AS [local_host],
                Node.value('(event/data/value)[27]', 'varchar(15)') AS [remote_host]
                INTO SD_events_RB_Connectivity
                FROM RBConnectivity
                ORDER BY 1
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_events_RB_Connectivity;
        WITH RBConnectivity(Node) AS (
            SELECT EventData.query('//*/RingBufferTarget/event[@name = ''connectivity_ring_buffer_recorded'']') 
            FROM SQLDIAG_XELData
            WHERE object_name = 'component_health_result' AND
                EventData.exist('//*/RingBufferTarget/event[@name = ''connectivity_ring_buffer_recorded'']') = 1
            ) --CTE:RBConnectivity
        INSERT INTO SD_events_RB_Connectivity
        SELECT DISTINCT
                Node.value('(/event/@timestamp)[1]', 'datetime') AS RBEventTimeStampUTC,
                Node.value('(event/data/value)[1]', 'varchar(10)') AS ID,
                Node.value('(event/data/value)[2]', 'varchar(20)') AS [timestamp],
                Node.value('(event/data/value)[3]', 'varchar(10)') AS [ConnectivityRecordType],
                Node.value('(event/data/text)[1]', 'varchar(20)') AS [ConnectivityRecordTypeDesc],
                Node.value('(event/data/value)[4]', 'varchar(20)') AS [Source],
                Node.value('(event/data/text)[2]', 'varchar(20)') AS [SourceType],
                Node.value('(event/data/value)[5]', 'varchar(10)') AS [SessionID],
                Node.value('(event/data/value)[6]', 'varchar(10)') AS [OSError],
                Node.value('(event/data/value)[7]', 'varchar(10)') AS [SNIError],
                Node.value('(event/data/value)[8]', 'varchar(10)') AS [SNIConsumerError],
                Node.value('(event/data/value)[9]', 'varchar(10)') AS [SNIProvider],
                Node.value('(event/data/value)[10]', 'varchar(10)') AS [State],
                Node.value('(event/data/value)[11]', 'varchar(10)') AS [LocalPort],
                Node.value('(event/data/value)[12]', 'varchar(10)') AS [RemotePort],
                Node.value('(event/data/value)[13]', 'varchar(10)') AS [TDSInputBufferError],
                Node.value('(event/data/value)[14]', 'varchar(10)') AS [TDSOutputBufferError],
                Node.value('(event/data/value)[15]', 'varchar(10)') AS [TDSInputBufferBYtes],
                Node.value('(event/data/value)[16]', 'varchar(10)') AS [TDSFlag],
                Node.value('(event/data/text)[3]', 'varchar(30)') AS [TDSFlagDesc],
                Node.value('(event/data/value)[17]', 'varchar(10)') AS [total_login_time_ms],
                Node.value('(event/data/value)[18]', 'varchar(10)') AS [login_task_enqueued_ms],
                Node.value('(event/data/value)[19]', 'varchar(10)') AS [network_writes_ms],
                Node.value('(event/data/value)[20]', 'varchar(10)') AS [network_reads_ms],
                Node.value('(event/data/value)[21]', 'varchar(10)') AS [ssl_processing_ms],
                Node.value('(event/data/value)[22]', 'varchar(10)') AS [sspi_processing_ms],
                Node.value('(event/data/value)[23]', 'varchar(10)') AS [login_trigger_and_resource_governor_processing_ms],
                Node.value('(event/data/value)[24]', 'varchar(36)') AS [connection_id],
                Node.value('(event/data/value)[25]', 'varchar(36)') AS [connection_peer_id],
                Node.value('(event/data/value)[26]', 'varchar(15)') AS [local_host],
                Node.value('(event/data/value)[27]', 'varchar(15)') AS [remote_host]
                FROM RBConnectivity
                ORDER BY 1
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH


-- Create table for "security_error_ring_buffer_recorded" events
BEGIN TRY
        WITH RBSecurity(Node) AS (
            SELECT EventData.query('//*/RingBufferTarget/event[@name = ''security_error_ring_buffer_recorded'']') 
            FROM SQLDIAG_XELData
            WHERE object_name = 'component_health_result' AND
                EventData.exist('//*/RingBufferTarget/event[@name = ''security_error_ring_buffer_recorded'']') = 1
            ) --CTE:RBSecurity
        SELECT DISTINCT
                Node.value('(/event/@timestamp)[1]', 'datetime') AS RBEventTimeStampUTC,
                Node.value('(event/data/value)[1]', 'varchar(10)') AS ID,
                Node.value('(event/data/value)[2]', 'varchar(20)') AS [timestamp],
                Node.value('(event/data/value)[3]', 'varchar(10)') AS [SessionID],
                Node.value('(event/data/value)[4]', 'varchar(10)') AS [ErrorCode],
                Node.value('(event/data/value)[5]', 'varchar(30)') AS [APIName],
                Node.value('(event/data/value)[6]', 'varchar(30)') AS [CallingAPIName]
                INTO SD_events_RB_Security
                FROM RBSecurity
                ORDER BY 1
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_events_RB_Security;
        WITH RBSecurity(Node) AS (
            SELECT EventData.query('//*/RingBufferTarget/event[@name = ''security_error_ring_buffer_recorded'']') 
            FROM SQLDIAG_XELData
            WHERE object_name = 'component_health_result' AND
                EventData.exist('//*/RingBufferTarget/event[@name = ''security_error_ring_buffer_recorded'']') = 1
            ) --CTE:RBSecurity
        INSERT INTO SD_events_RB_Security
        SELECT DISTINCT
                Node.value('(/event/@timestamp)[1]', 'datetime') AS RBEventTimeStampUTC,
                Node.value('(event/data/value)[1]', 'varchar(10)') AS ID,
                Node.value('(event/data/value)[2]', 'varchar(20)') AS [timestamp],
                Node.value('(event/data/value)[3]', 'varchar(10)') AS [SessionID],
                Node.value('(event/data/value)[4]', 'varchar(10)') AS [ErrorCode],
                Node.value('(event/data/value)[5]', 'varchar(30)') AS [APIName],
                Node.value('(event/data/value)[6]', 'varchar(30)') AS [CallingAPIName]
                FROM RBSecurity
                ORDER BY 1
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH

-- Create table for "SD_AGState" events
BEGIN TRY
    SELECT CAST(object_name as VARCHAR(15)) ObjectName, 
    EventData.value('(event/data/value)[9]', 'varchar(25)') AS NodeName,
    EventData.value('(event/data/value)[8]', 'varchar(25)') AS InstanceName,
    EventData.value('(event/data/value)[5]', 'varchar(max)') AS AGName,
    EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data/value)[3]', 'datetime') AS CreationTimeUTC,
    EventData.value('(event/data/value)[1]', 'varchar(10)') AS [State],
    EventData.value('(event/data/value)[6]', 'varchar(25)') AS State_Desc,
    EventData.value('(event/data/value)[2]', 'varchar(25)') AS FailureConditionLevel,
    EventData.value('(event/data/value/availabilityGroup/@resourceID)[1]', 'varchar(36)') AS AGResourceID,
    EventData.value('(event/data/value/availabilityGroup/@leaseValid)[1]', 'varchar(10)') AS LeaseValid
    INTO SD_AGState
    FROM SQLDIAG_XELData
    WHERE object_name =   'component_health_result' AND 
        EventData.value('(event/data/value)[4]', 'varchar(max)') = 'alwaysOn:AvailabilityGroup';
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() = 2714) BEGIN
        TRUNCATE TABLE SD_AGState
        INSERT INTO SD_AGState
        SELECT CAST(object_name as VARCHAR(15)) ObjectName, 
        EventData.value('(event/data/value)[9]', 'varchar(25)') AS NodeName,
        EventData.value('(event/data/value)[8]', 'varchar(25)') AS InstanceName,
        EventData.value('(event/data/value)[5]', 'varchar(max)') AS AGName,
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data/value)[3]', 'datetime') AS CreationTimeUTC,
        EventData.value('(event/data/value)[1]', 'varchar(10)') AS [State],
        EventData.value('(event/data/value)[6]', 'varchar(25)') AS State_Desc,
        EventData.value('(event/data/value)[2]', 'varchar(25)') AS FailureConditionLevel,
        EventData.value('(event/data/value/availabilityGroup/@resourceID)[1]', 'varchar(36)') AS AGResourceID,
        EventData.value('(event/data/value/availabilityGroup/@leaseValid)[1]', 'varchar(10)') AS LeaseValid
        FROM SQLDIAG_XELData
        WHERE object_name =   'component_health_result' AND 
            EventData.value('(event/data/value)[4]', 'varchar(max)') = 'alwaysOn:AvailabilityGroup';
    END ELSE
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
END CATCH



--sample queries
SELECT * FROM SD_resource WHERE State_Desc <> 'clean' ORDER BY TimeStampUTC
SELECT * FROM SD_iosubsystem where totalLongIos > 0 ORDER BY TimeStampUTC 
SELECT * FROM SD_iosubsystem where State_Desc <> 'clean' ORDER BY TimeStampUTC
SELECT * FROM SD_iosubsystem where duration > 0 ORDER BY TimeStampUTC
SELECT * FROM SD_iosubsystem where ioLatchTimeouts > 0 ORDER BY TimeStampUTC
SELECT 'Max duration event:', * FROM SD_iosubsystem WHERE duration in (SELECT max(duration) FROM SD_iosubsystem)
SELECT duration [Duration ms], count(duration) Count FROM SD_iosubsystem
    WHERE duration IS NOT NULL
    GROUP BY duration ORDER BY duration
SELECT * FROM SD_query where trackingNonYieldingScheduler <> '0x0' ORDER BY TimeStampUTC 
SELECT * FROM SD_query where State_Desc <> 'clean' ORDER BY TimeStampUTC
SELECT * FROM SD_System where nonYieldingTasksReported <> 0 ORDER BY TimeStampUTC 
SELECT * FROM SD_System WHERE State_Desc <> 'clean' ORDER BY TimeStampUTC
SELECT * FROM SD_AGStatusChange ORDER BY TimeStampUTC

--just list health state messages
SELECT * FROM SD_InfoMessage 
    WHERE InfoMessage like '%health state%'
    ORDER BY TimeStampUTC

--list other info messages
SELECT ObjectName, TimeStampUTC, NodeName, InstanceName,
    InfoMessage FROM
    SD_InfoMessage WHERE InfoMessage not like '%health state%%'
    ORDER BY TimeStampUTC


SELECT * FROM SD_misc ORDER BY TimeStampUTC
SELECT * FROM SD_events_RB_error_reported ORDER BY RBEventTimeStampUTC
SELECT * FROM SD_events_RB_schedmon ORDER BY RBEventTimeStampUTC
SELECT * FROM SD_events_RB_ResourceMon ORDER BY RBEventTimeStampUTC
SELECT * FROM SD_events_RB_Connectivity ORDER BY RBEventTimeStampUTC
SELECT * FROM SD_events_RB_Security ORDER BY RBEventTimeStampUTC

SELECT TOP 200 * FROM SD_AGState ORDER BY TimeStampUTC
