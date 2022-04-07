/*****************************************************************
  This script uses the CTRL-SHIFT-M option to substitute
  default parameters with actual parameters.
  There are two varibles that need to be set by these parameters:
  @XELPath   -- where the file is located
  @XELFile   -- the name of the file to be imported - wildcards accepted.
  
  Using CTRL-SHIFT-M  (menu item:   QUERY->Specifiy Values for Template Parameters)
  will pop up a dialog where the two parameters can be assigned values.
  Once this is done, the script can be run to parse and analyze
  the collected information.
  
  This script is provided "AS IS" with no warranties, and confers no rights.
  Use of included script samples are subject to the terms specified at
  http://www.microsoft.com/info/cpyright.htm

******************************************************************/


SET NOCOUNT ON
USE [master]
GO

--construct path & file name for WaitInfo_*.xel files to load
DECLARE @XELPath VARCHAR(max) = '<XEL Folder Path, varchar(max), D:\Path\Where\AO Health XEL Files are stored\>'
IF RIGHT(@XELPath, 1) <> '\'
    SELECT @XELPath += '\'
DECLARE @XELFile VARCHAR(max) = @XELPath + '<XELFile, varchar(max), *waitinfo*.xel>';

--shred wait_info Xevents
WITH EventData_CTE (object_name, EventData)
AS
(
    SELECT object_name, cast(event_data as XML) EventData
    FROM sys.fn_xe_file_target_read_file(
    @XELFile, NULL, null, null)
)
SELECT object_name, EventData.value('(event/@timestamp)[1]', 'datetime2') AS TimeStamp,
    EventData.value('(event/data[@name="wait_type"]/text)[1]', 'varchar(max)') AS WaitType,
    EventData.value('(event/data[@name="duration"]/value)[1]', 'bigint') AS Duration,
    EventData.value('(event/data[@name="signal_duration"]/value)[1]', 'bigint') AS Signal_Duration,
    EventData.value('(event/action[@name="session_id"]/value)[1]', 'int') AS Session_ID,
    EventData.value('(event/action[@name="scheduler_id"]/value)[1]', 'int') AS Scheduler_ID,
    EventData.value('(event/action[@name="event_sequence"]/value)[1]', 'int') AS EventSequenceNum,
    EventData
    INTO #WaitInfo
    FROM EventData_CTE;

   SELECT Session_ID, WaitType, count(WaitType) AS Counts, 
       SUM(Duration) As Sum_Duration, 
       SUM(Signal_Duration) as Sum_SignalDuration
       FROM #WaitInfo
       GROUP BY Session_ID, WaitType
       ORDER BY Session_ID, Count(WaitType) DESC

   SELECT Session_ID, WaitType, count(WaitType) AS Counts, 
       SUM(Duration) As Sum_Duration, 
       SUM(Signal_Duration) as Sum_SignalDuration
       FROM #WaitInfo
       GROUP BY Session_ID, WaitType
       ORDER BY Session_ID, SUM(Duration) DESC

