/*=====================================================================
AUTHOR:    trayce@seekwellandprosper.com
FILENAME:  Shred_AOHealth_XEL.sql
VERSION 2.2
NOTES:

  use the CTRL-SHIFT-M macro substitution

  Database_name -- where the shredding script will store its data
                                okay for database to already to exist.
                                If the destination tables exist, they will be truncated and reloaded.

  XEL Folder path -- the path (relative to the SQL instance) of where the
                                AlwaysOn_health*.xel files are located

  XEL File              -- filename (or wild card specification) of file to be shredded
                                by default the wildcard is "AlwaysOn_health*.xel" to shred
                                all AlwaysOn Health XEL files in the specified folder.

TABLES OUTPUT
==============
    dbo.AO_ddl_executed                                         -- DDL events captured in AO health XEL session
    dbo.AO_lease_expired                                        -- contains lease expiration events
    dbo.AOHealth_XELData                                        -- imported raw Xevent data
    dbo.AR_state		                                -- current availability replica state xevents for individual AGs
    dbo.AR_state_change                                         -- state changes for the individual AGs
    dbo.error_reported                                          -- all error/info messages logged in AO health XEL session
    dbo.AR_Repl_Mgr_State_change                                -- state changes for the instance availability replica
    dbo.lock_redo_blocked	                                -- blocked redo xevents
    dbo.hadr_db_partner_set_sync_state		                --partner sync state xevents
    dbo.availability_replica_automatic_failover_validation	--failover validation xevents
	dbo.AOHealthSummary										--holds summary count info for each event

CHANGE HISTORY:
---------------------------
2019/05/16 Version 2.2		added ddl_phase_desc to DDL event queries
2017/03/24 Version 2.1		changed where clauses to use object_name
							only return XEvents that are found
							added summary table of events & their counts
							wrapped IsNull around a value that is NULL in SQL 2012
2017/01/25 Version 2.0		re-vamped table creation
							added new xevents
							changed XML shredding style
							remove xml indexes
2015/09/11  Added processing for lock_redo_blocked  events
2015/08/21  Modified comments
2015/08/12  Changed all "TimeStamp" column names to TimeStampUTC

2015/07/28
        Added these notes at top of script.
        Added AO lease expiration events.   Table:  dbo.AO_lease_expired.
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
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 5039) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    RAISERROR ('Severe error.  Terminating connection...', 19, 1) WITH LOG
    END
END CATCH

USE [DANA1ESDB1E] 

--construct path & file name for SQLDIAG_*.xel files to load
DECLARE @XELPath VARCHAR(max) = '<XEL Folder Path, varchar(max), D:\Path\Where\AO Health XEL Files are stored\>'
IF RIGHT(@XELPath, 1) <> '\'
    SELECT @XELPath += '\'
DECLARE @XELFile VARCHAR(max) = @XELPath + '<XELFile, varchar(max), AlwaysOn_health*.xel>'

--create table, indexes
BEGIN TRY
    DROP TABLE AOHealth_XELData
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 3701) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    END
END CATCH
CREATE TABLE AOHealth_XELData
    (ID INT IDENTITY PRIMARY KEY CLUSTERED,
    object_name varchar(max),
    EventData XML,
    file_name varchar(max),
    file_offset bigint);

--read from the files into the table
INSERT INTO AOHealth_XELData
SELECT object_name, cast(event_data as XML) AS EventData,
  file_name, File_Offset
  FROM sys.fn_xe_file_target_read_file(
  @XELFile, NULL, null, null);

--create summary table of Events
--pre-populate with the event types and "0" for count.
BEGIN TRY
    DROP TABLE AOHealthSummary 
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 3701) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    END
END CATCH
CREATE TABLE AOHealthSummary (XEvent varchar(50), [COUNT] INT);
INSERT INTO AOHealthSummary VALUES('error_reported', 0)
INSERT INTO AOHealthSummary VALUES('alwayson_ddl_executed', 0)
INSERT INTO AOHealthSummary VALUES('availability_group_lease_expired',0)
INSERT INTO AOHealthSummary VALUES('availability_replica_manager_state_change', 0)
INSERT INTO AOHealthSummary VALUES('availability_replica_state', 0)
INSERT INTO AOHealthSummary VALUES('availability_replica_state_change', 0)
INSERT INTO AOHealthSummary VALUES('lock_redo_blocked', 0)
IF SERVERPROPERTY('ProductMajorVersion') >=12 BEGIN
	INSERT INTO AOHealthSummary VALUES('hadr_db_partner_set_sync_state', 0)
	INSERT INTO AOHealthSummary VALUES('availability_replica_automatic_failover_validation', 0)
END

-- Create table for "error_reported" events
BEGIN TRY
    DROP TABLE error_reported
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 3701) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    END
END CATCH
CREATE TABLE error_reported (TimeStampUTC DATETIME, 
	error_number INT, 
	severity INT, 
	state INT, 
	user_defined varchar(5),
	category_desc varchar(25),
	category varchar(5),
	destination varchar(20),
	destination_desc varchar(20),
	is_intercepted varchar(5),
	message varchar(max))

INSERT INTO error_reported
SELECT  EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data[@name="error_number"]/value)[1]', 'int') AS error_number,
    EventData.value('(event/data[@name="severity"]/value)[1]', 'int') AS severity,
    EventData.value('(event/data[@name="state"]/value)[1]', 'int') AS state,
    EventData.value('(event/data[@name="user_defined"]/value)[1]', 'varchar(5)') AS user_defined,
    EventData.value('(event/data[@name="category"]/text)[1]', 'varchar(25)') AS category_desc,
    EventData.value('(event/data[@name="category"]/value)[1]', 'varchar(5)') AS category,
    EventData.value('(event/data[@name="destination"]/value)[1]', 'varchar(20)') AS destination,
    EventData.value('(event/data[@name="destination"]/text)[1]', 'varchar(20)') AS destination_desc,
    EventData.value('(event/data[@name="is_intercepted"]/value)[1]', 'varchar(5)') AS is_intercepted,
    EventData.value('(event/data[@name="message"]/value)[1]', 'varchar(max)') AS message
    FROM AOHealth_XELData
    WHERE object_name = 'error_reported';


-- Create table for "alwayson_ddl_executed" events
BEGIN TRY
    DROP TABLE AO_ddl_executed
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 3701) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    END
END CATCH
CREATE TABLE AO_ddl_executed (Xevent varchar(34),
	TimeStampUTC DATETIME,
	ddl_action int,
	ddl_action_desc varchar(max),
	ddl_phase int,
	ddl_phase_desc varchar(10),
	availability_group_name varchar(25),
	availability_group_id varchar(36),
	[statement] varchar(max))

INSERT INTO AO_ddl_executed
SELECT cast(object_name as varchar(34)) AS XEvent, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    	EventData.value('(event/data[@name="ddl_action"]/value)[1]', 'int') AS ddl_action,
    	EventData.value('(event/data[@name="ddl_action"]/text)[1]', 'varchar(max)') AS ddl_action_desc,
    	EventData.value('(event/data[@name="ddl_phase"]/value)[1]', 'int') AS ddl_phase,
    	EventData.value('(event/data[@name="ddl_phase"]/text)[1]', 'varchar(10)') AS ddl_phase_desc,
    	EventData.value('(event/data[@name="availability_group_name"]/value)[1]', 'varchar(25)') AS availability_group_name,
    	EventData.value('(event/data[@name="availability_group_id"]/value)[1]', 'varchar(36)') AS availability_group_id,
    	EventData.value('(event/data[@name="statement"]/value)[1]', 'varchar(max)') AS [statement]
       	FROM AOHealth_XELData
      	WHERE object_name = 'alwayson_ddl_executed';


-- Create table for "lease expiration" events
BEGIN TRY
	DROP TABLE AO_lease_expired
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 3701) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    END
END CATCH
CREATE TABLE AO_lease_expired(Xevent varchar(33), 
	TimeStampUTC DATETIME,
	AGName varchar(25),
	AG_ID varchar(36))

INSERT INTO AO_lease_expired
SELECT  cast(object_name as varchar(33)) AS XEvent, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
	EventData.value('(event/data[@name="availability_group_name"]/value)[1]', 'varchar(25)') AS AGName,
	EventData.value('(event/data[@name="availability_group_id"]/value)[1]', 'varchar(36)') AS AG_ID
        FROM AOHealth_XELData
        WHERE object_name = 'availability_group_lease_expired';


-- Create table for "availability_replica_manager_state_change" events
BEGIN TRY
	DROP TABLE AR_Repl_Mgr_State_Change
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 3701) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    END
END CATCH
CREATE TABLE AR_Repl_Mgr_State_Change(XEvent varchar(42),
	TimeStampUTC datetime,
	current_state INT,
	current_state_desc varchar(30))

INSERT INTO AR_Repl_Mgr_State_Change
SELECT cast(object_name as varchar(42)) AS XEvent, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data[@name="current_state"]/value)[1]', 'int') AS current_state,
    EventData.value('(event/data[@name="current_state"]/text)[1]', 'varchar(30)') AS current_state_desc
    FROM AOHealth_XELData
    WHERE object_name = 'availability_replica_manager_state_change';

-- Create table for "availability_replica_state" events
BEGIN TRY
	DROP TABLE AR_state
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 3701) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    END
END CATCH
CREATE TABLE AR_state(XEvent varchar(42),
	TimeStampUTC datetime,
	current_state int,
	current_state_desc varchar(20),
	availability_group_name varchar(36),
	availablity_group_id varchar(36),
	availability_replica_id varchar(36))

INSERT INTO AR_state
SELECT cast(object_name as varchar(34)) AS XEvent, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data[@name="current_state"]/value)[1]', 'int') AS current_state,
    EventData.value('(event/data[@name="current_state"]/text)[1]', 'varchar(20)') AS current_state_desc,
    EventData.value('(event/data[@name="availability_group_name"]/value)[1]', 'varchar(36)') AS availability_group_name,
    EventData.value('(event/data[@name="availability_group_id"]/value)[1]', 'varchar(36)') AS availability_group_id,
    EventData.value('(event/data[@name="availability_replica_id"]/value)[1]', 'varchar(36)') AS availability_replica_id
    FROM AOHealth_XELData
    WHERE object_name = 'availability_replica_state'
	ORDER BY EventData.value('(event/@timestamp)[1]', 'datetime');


-- Create table for "availability_replica_state_change" events
BEGIN TRY
	DROP TABLE AR_state_change
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 3701) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    END
END CATCH
CREATE TABLE AR_state_change(XEvent varchar(42),
	TimeStampUTC datetime,
	availability_replica_name varchar(25),
	availability_group_name varchar(25),
	previous_state int,
	previous_state_desc varchar(30),
	current_state int,
	current_state_desc varchar(30),
	availability_replica_id varchar(36),
	availability_group_id varchar(36))

INSERT INTO AR_state_change
SELECT cast(object_name as varchar(34)) AS XEvent, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
	IsNULL(EventData.value('(event/data[@name="availability_replica_name"]/value)[1]', 'varchar(25)'), 'Data Unavailable') AS availability_replica_name,
    EventData.value('(event/data[@name="availability_group_name"]/value)[1]', 'varchar(25)') AS availability_group_name,
    EventData.value('(event/data[@name="previous_state"]/value)[1]', 'int') AS previous_state,
    EventData.value('(event/data[@name="previous_state"]/text)[1]', 'varchar(30)') AS previous_state_desc,
    EventData.value('(event/data[@name="current_state"]/value)[1]', 'int') AS current_state,
    EventData.value('(event/data[@name="current_state"]/text)[1]', 'varchar(30)') AS current_state_desc,
    EventData.value('(event/data[@name="availability_replica_id"]/value)[1]', 'varchar(36)') AS availability_replica_id,
    EventData.value('(event/data[@name="availability_group_id"]/value)[1]', 'varchar(36)') AS availability_group_id
	FROM AOHealth_XELData
    WHERE object_name = 'availability_replica_state_change'
	ORDER BY EventData.value('(event/@timestamp)[1]', 'datetime');


-- Create table for "lock_redo_blocked" events
BEGIN TRY
	DROP TABLE lock_redo_blocked
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 3701) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    END
END CATCH

CREATE TABLE lock_redo_blocked(XEvent varchar(42),
	TimeStampUTC datetime,
	ResourceType int,
	ResourceTypeDesc varchar(25),
	Mode int,
	ModeDesc varchar(25),
	OwnerType int,
	OwnerTypeDesc varchar(25),
	TransactionID bigint,
	database_id int,
	lockspace_workspace_id varchar(22),
	lockspace_sub_id bigint,
	lockspace_nest_id bigint,
	resource_0 bigint,
	resource_1 bigint,
	resource_2 bigint,
	[object_id] bigint,
	associated_object_id bigint,
	duration int,
	resource_description varchar(25))

INSERT INTO lock_redo_blocked
    SELECT cast(object_name as varchar(42)) AS XEvent, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
	EventData.value('(event/data[@name="resource_type"]/value)[1]', 'int') AS ResourceType,
	EventData.value('(event/data[@name="resource_type"]/text)[1]', 'varchar(25)') AS ResourceTypeDesc,
	EventData.value('(event/data[@name="mode"]/value)[1]', 'int') AS Mode,
	EventData.value('(event/data[@name="mode"]/text)[1]', 'varchar(25)') AS ModeDesc,
	EventData.value('(event/data[@name="owner_type"]/value)[1]', 'int') AS OwnerType,
	EventData.value('(event/data[@name="owner_type"]/text)[1]', 'varchar(25)') AS OwnerTypeDesc,
	EventData.value('(event/data[@name="transaction_id"]/value)[1]', 'bigint') AS transaction_id,
	EventData.value('(event/data[@name="database_id"]/value)[1]', 'int') AS database_id,
	EventData.value('(event/data[@name="lockspace_workspace_id"]/value)[1]', 'varchar(22)') AS lockspace_workspace_id,
	EventData.value('(event/data[@name="lockspace_sub_id"]/value)[1]', 'bigint') AS lockspace_sub_id,
	EventData.value('(event/data[@name="lockspace_nest_id"]/value)[1]', 'bigint') AS lockspace_nest_id,
	EventData.value('(event/data[@name="resource_0"]/value)[1]', 'bigint') AS resource_0,
	EventData.value('(event/data[@name="resource_1"]/value)[1]', 'bigint') AS resource_1,
	EventData.value('(event/data[@name="resource_2"]/value)[1]', 'bigint') AS resource_2,
	EventData.value('(event/data[@name="object_id"]/value)[1]', 'bigint') AS [object_id],
	EventData.value('(event/data[@name="associated_object_id"]/value)[1]', 'bigint') AS associated_object_id,
	EventData.value('(event/data[@name="duration"]/value)[1]', 'int') AS duration,
	EventData.value('(event/data[@name="resource_description"]/value)[1]', 'varchar(25)') AS resource_description
    FROM AOHealth_XELData
    WHERE object_name = 'lock_redo_blocked'
	ORDER BY EventData.value('(event/@timestamp)[1]', 'datetime');

-- Create table for "hadr_db_partner_set_sync_state" events
BEGIN TRY
	DROP TABLE hadr_db_partner_set_sync_state
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 3701) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    END
END CATCH

CREATE TABLE hadr_db_partner_set_sync_state(XEvent varchar(42),
	TimeStampUTC datetime,
	database_id int,
	commit_policy int,
	commit_policy_desc varchar(20),
	commit_policy_target int,
	commit_policy_target_desc varchar(20),
	synct_state int,
	sync_state_desc varchar(20),
	sync_log_block varchar(20),
	group_id varchar(36),
	replica_id varchar(36),
	ag_database_id varchar(36))
 
INSERT INTO hadr_db_partner_set_sync_state
   SELECT cast(object_name as varchar(42)) AS XEvent, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
		EventData.value('(event/data[@name="database_id"]/value)[1]', 'int') AS database_id,
		EventData.value('(event/data[@name="commit_policy"]/value)[1]', 'int') AS commit_policy,
		EventData.value('(event/data[@name="commit_policy"]/text)[1]', 'varchar(20)') AS commit_policy_desc,
		EventData.value('(event/data[@name="commit_policy_target"]/value)[1]', 'int') AS commit_policy_target,
		EventData.value('(event/data[@name="commit_policy_target"]/text)[1]', 'varchar(20)') AS commit_policy_target_desc,
		EventData.value('(event/data[@name="sync_state"]/value)[1]', 'int') AS sync_state,
		EventData.value('(event/data[@name="sync_state_desc"]/text)[1]', 'varchar(20)') AS sync_state_desc,
		EventData.value('(event/data[@name="sync_log_block"]/value)[1]', 'varchar(20)') AS sync_log_block,
		EventData.value('(event/data[@name="group_id"]/value)[1]', 'varchar(36)') AS group_id,
		EventData.value('(event/data[@name="replica_id"]/value)[1]', 'varchar(36)') AS replica_id,
		EventData.value('(event/data[@name="ag_database_id"]/value)[1]', 'varchar(36)') AS ag_database_id
    FROM AOHealth_XELData
    WHERE object_name = 'hadr_db_partner_set_sync_state'
	ORDER BY EventData.value('(event/@timestamp)[1]', 'datetime');

-- Create table for "availability_replica_automatic_failover_validation" events
BEGIN TRY
	DROP TABLE availability_replica_automatic_failover_validation
END TRY
BEGIN CATCH
    IF (ERROR_NUMBER() <> 3701) BEGIN
    SELECT ERROR_NUMBER(), ERROR_MESSAGE()
    END
END CATCH

CREATE TABLE availability_replica_automatic_failover_validation (XEvent varchar(42),
	TimeStampUTC datetime,
	availability_replica_name varchar(25),
    availability_group_name varchar(25),
    availability_replica_id varchar(36),
    availability_group_id varchar(36),
    forced_quorum varchar(5),
    joined_and_synchronized varchar(5),
    previous_primary_or_automatic_failover_target varchar(5))

INSERT INTO availability_replica_automatic_failover_validation
   SELECT cast(object_name as varchar(42)) AS XEvent, EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
    EventData.value('(event/data[@name="availability_replica_name"]/value)[1]', 'varchar(25)') AS availability_replica_name,
    EventData.value('(event/data[@name="availability_group_name"]/value)[1]', 'varchar(25)') AS availability_group_name,
    EventData.value('(event/data[@name="availability_replica_id"]/value)[1]', 'varchar(36)') AS availability_replica_id,
    EventData.value('(event/data[@name="availability_group_id"]/value)[1]', 'varchar(36)') AS availability_group_id,
    EventData.value('(event/data[@name="forced_quorum"]/value)[1]', 'varchar(5)') AS forced_quorum,
    EventData.value('(event/data[@name="joined_and_synchronized"]/value)[1]', 'varchar(5)') AS joined_and_synchronized,
    EventData.value('(event/data[@name="previous_primary_or_automatic_failover_target"]/value)[1]', 'varchar(5)') AS previous_primary_or_automatic_failover_target
    FROM AOHealth_XELData
    WHERE object_name = 'availability_replica_automatic_failover_validation'
	ORDER BY EventData.value('(event/@timestamp)[1]', 'datetime');

GO
SET NOCOUNT ON

IF EXISTS(SELECT * FROM error_reported) 
BEGIN
	PRINT 'Error events'
	PRINT '============';
	--display results from "error_reported" event data
	WITH ErrorCTE (ErrorNum, ErrorCount, FirstDate, LastDate) AS (
	SELECT error_number, Count(error_number), min(TimeStampUTC), max(TimeStampUTC) As ErrorCount FROM error_reported
		GROUP BY error_number) 
	SELECT CAST(ErrorNum as CHAR(10)) ErrorNum,
		CAST(ErrorCount as CHAR(10)) ErrorCount,
		CONVERT(CHAR(25), FirstDate,121) FirstDate,
		CONVERT(CHAR(25), LastDate, 121) LastDate,
			CAST(CASE ErrorNum 
			WHEN 35202 THEN 'A connection for availability group ... has been successfully established...'
			WHEN 1480 THEN 'The %S_MSG database "%.*ls" is changing roles ... because the AG failed over ...'
			WHEN 35206 THEN 'A connection timeout has occurred on a previously established connection ...'
			WHEN 35201 THEN 'A connection timeout has occurred while attempting to establish a connection ...'
			WHEN 41050 THEN 'Waiting for local WSFC service to start.'
			WHEN 41051 THEN 'Local WSFC service started.'
			WHEN 41052 THEN 'Waiting for local WSFC node to start.'
			WHEN 41053 THEN 'Local WSFC node started.'
			WHEN 41054 THEN 'Waiting for local WSFC node to come online.'
			WHEN 41055 THEN 'Local WSFC node is online.'
			WHEN 41048 THEN 'Local WSFC service has become unavailable.'
			WHEN 41049 THEN 'Local WSFC node is no longer online.'
			ELSE m.text END AS VARCHAR(81)) [Abbreviated Message]
		 FROM
		ErrorCTE ec LEFT JOIN sys.messages m on ec.ErrorNum = m.message_id
		and m.language_id = 1033
	order by CAST(ErrorCount as INT) DESC
END

IF EXISTS(SELECT * FROM AO_ddl_executed) 
BEGIN
	PRINT 'Non-failover DDL Events'
	PRINT '=======================';
	SELECT TimeStampUTC, CAST(ddl_phase as varchar(10)) ddl_phase,
		CAST(ddl_phase_desc as varchar(10)) ddl_phase_desc,
		CASE WHEN LEN([statement]) > 220
		THEN CAST([statement] as varchar(1155)) + char(10) 
		ELSE CAST(Replace([statement], char(10), '') as varchar(220)) 
		END as [statement]
		FROM AO_ddl_executed WHERE [statement] NOT LIKE '%FAILOVER%'
			OR ([statement] LIKE '%FAILOVER%' AND [statement] LIKE '%CREATE%')
		ORDER BY TimeStampUTC

	PRINT 'Failover DDL Events'
	PRINT '=======================';
	-- Display results "alwayson_ddl_executed" events
	SELECT TimeStampUTC, CAST(ddl_phase as varchar(10)) ddl_phase, 
		CAST(ddl_phase_desc as varchar(10)) ddl_phase_desc, 
		CAST(Replace([statement], char(10), '') as varchar(80)) as [statement]
		FROM AO_ddl_executed WHERE ([statement] LIKE '%FAILOVER%' OR [statement] LIKE '%FORCE%')
			AND [statement] not like 'CREATE%'
		ORDER BY TimeStampUTC
END

IF EXISTS(SELECT * FROM AR_Repl_Mgr_State_Change)
BEGIN
	PRINT 'Availability Replica Manager state changes'
	PRINT '==========================================';
	-- display results for "availability_replica_manager_state_change" events
	SELECT  CONVERT(char(25), TimeStampUTC, 121) TimeStampUTC, 
		CAST(current_state_desc as CHAR(30)) [State]
	FROM AR_Repl_Mgr_State_Change ORDER BY TimeStampUTC
END

IF EXISTS(SELECT * FROM AR_State) 
BEGIN
	PRINT 'Availability Replica state'
	PRINT '==========================';
	-- display results for "availability_replica_state" events
	SELECT * FROM AR_State
		ORDER BY TimeStampUTC
END

IF EXISTS(SELECT * FROM AR_State_Change) 
BEGIN
	PRINT 'Availability Replica state changes'
	PRINT '==================================';
	-- display results for "availability_replica_state_change" events
	SELECT TimeStampUTC, availability_group_name AGName,
		previous_state_desc as [Prev state],
		current_state_desc as [New State] FROM AR_State_Change
		ORDER BY TimeStampUTC
END

IF EXISTS(SELECT * FROM AO_lease_expired) 
BEGIN
	PRINT 'Lease Expiration Events'
	PRINT '=======================';
	-- Display results "lease expiration" events
	SELECT TimeStampUTC, CAST(AGName as varchar(25)) AGName, 
		CAST(AG_ID as varchar(36)) AG_ID
		FROM AO_lease_expired
		ORDER BY TimeStampUTC
END

IF EXISTS(SELECT * FROM lock_redo_blocked) 
BEGIN
	PRINT 'BLOCKED REDO Events'
	PRINT '===================';
	-- Display results "lock_redo_blocked" events
	SELECT *
		FROM lock_redo_blocked
		ORDER BY TimeStampUTC
END

IF EXISTS(SELECT * FROM hadr_db_partner_set_sync_state) 
BEGIN
	PRINT 'hadr_db_partner_set_sync_state'
	PRINT '=====================================';
	-- Display results "hadr_db_partner_set_sync_state" events
	SELECT *
		FROM hadr_db_partner_set_sync_state
		ORDER BY TimeStampUTC
END

IF EXISTS(SELECT * FROM availability_replica_automatic_failover_validation) 
BEGIN
	PRINT 'availability_replica_automatic_failover_validation'
	PRINT '==================================================';
	-- Display results "availability_replica_automatic_failover_validation" events
	SELECT *
		FROM availability_replica_automatic_failover_validation
		ORDER BY TimeStampUTC
END;

--print out summary of AO Health XEvents found
With Summary (XEvent, [Count])
AS (SELECT CAST(object_name AS VARCHAR(50)) AS [XEvent], count(*) AS [Count] 
	FROM AOHealth_XELData
	GROUP BY object_name)
UPDATE AOHealthSummary
	SET [COUNT] = s.[COUNT] 
	FROM Summary s
	INNER JOIN AOHealthSummary ao ON s.XEvent = ao.XEvent;

IF EXISTS(SELECT * FROM AOHealthSummary) BEGIN
	PRINT 'Summary event counts for AO Health XEvents'
	PRINT '==========================================';
	-- Display event counts for AO Health XEvent data
	SELECT * FROM AOHealthSummary
	ORDER BY [count] DESC, XEvent
END
