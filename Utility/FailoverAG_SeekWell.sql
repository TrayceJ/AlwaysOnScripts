/*************************************************************************************************
AUTHOR:    trayce@seekwellandprosper.com
FILENAME:  FailoverAG.sql
VERSION:   1.0
NOTES:
			This script is for demonstration purposes only and should not be used in production
			without independent review and testing.
			No warranty, service, or proper execution is expressed or implied.
			

			This script will attempt to perform an Availability Group failover.
			Before attempting failover, it checks to make sure the following conditions are met:
			
				The replica is connected to the primary  (@ConnectedState = 1)
				The replica is configured for SYNCHRONOUS mode (@SyncMode = 1)
				The replica's operational state is ONLINE (@OperationalState = 2)
				The role of the replica is SECONDARY (@ReplicaRole = 2)
				The recovery health of the replica is ONLINE (@RecoveryHealth = 1)
				The synchronization state is "healthy" (@SyncState = 2)

			If all of the conditions are met, then executing this script will issue an
			      ALTER AG ...FAILOVER command.
			It must be run on the secondary to which you want to failover and make the primary.

			<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
			<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
			IF SUCCESSFUL, THE AG WILL BE FAILED OVER - CAUSING ALL CONNECTIONS TO DATABASES
			WITHIN THE AG TO BE SEVERED.
			<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
			<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

			This script only moves (fails over) one availabilty group at a time.


			BEFORE EXECUTION:    
				1) connect to the secondary that the AG will be failed over to -- to become primary.
				2) use the CTRl-SHIFT-M option  (or from the menu item:  QUERY->Specify Values For Template Parameters )
				   to fill in the name of the AG to failover, and the retry count.


			  This script uses the CTRL-SHIFT-M option to substitute default parameters with actual parameters.
			  There are two varibles that need to be set by these parameters:
				  
				  @AGName     -- the name of the AG to failover
				  @RetryCount -- how many times to attempt retry
  
			  Using CTRL-SHIFT-M  (menu item:   QUERY->Specifiy Values for Template Parameters)
			  will pop up a dialog where the two parameters can be assigned values.


CHANGE HISTORY:
---------------------------
2017/06/05	Initial revision

*************************************************************************************************/
BEGIN TRY
DECLARE @AGName sysname = '<AG Name, sysname, AG_TO_FAILOVER>';
DECLARE @RetryCount INT = CAST('<RetryCount, INT, 5>' AS INT);
DECLARE @MACRO sysname;
END TRY
BEGIN CATCH
END CATCH

SELECT @MACRO = '<AG Name'
SELECT @MACRO += ', sysname'
SELECT @MACRO += ', AG_TO_FAILOVER>'
IF (@AGName = @MACRO OR
	@AGName IS NULL OR
	@AGName = 'AG_TO_FAILOVER') BEGIN
	PRINT 'Invalid Availability Group Name.   Exiting .....'
	GOTO THE_END
END

--Check @RetryCount for legitimate values
IF @RetryCount < 1 or @RetryCount > 10 or @RetryCount IS NULL BEGIN
	SELECT @RetryCount = 5
END

DECLARE @SyncMode INT = NULL;
DECLARE @ReplicaRole INT = NULL;
DECLARE @OperationalState INT = NULL;
DECLARE @RecoveryHealth INT = NULL;
DECLARE @SyncState INT = NULL;
DECLARE @ConnectedState INT = NULL;
DECLARE @sql varchar(max) = '';
DECLARE @crlf char(2) = char(13) + char(10);
DECLARE @msg varchar(max);

--Replace []s with nothing, if brackets are provided
SELECT @AGName = REPLACE(REPLACE(@AGName, '[', ''), ']','');

/**************************************************
	Get the states of the replica, AG, & databases.
	Then attempt failover if all pre-reqs are met.
***************************************************/
SELECT 
	@SyncMode = ars.availability_mode,
	@ReplicaRole = rs.role,
	@OperationalState = rs.operational_state,
	@RecoveryHealth = rs.recovery_health,
	@SyncState = rs.synchronization_health,
	@ConnectedState = rs.connected_state 
	FROM sys.dm_hadr_availability_replica_states rs
	INNER JOIN sys.availability_groups ags
	ON rs.group_id = ags.group_id
	INNER JOIN sys.availability_replicas ars
	on rs.replica_id = ars.replica_id and rs.group_id = ars.group_id		
	WHERE rs.is_local = 1 and ags.name = @AGName;

IF (@ConnectedState = 1) BEGIN
	IF (@SyncMode = 1) BEGIN
		IF (@OperationalState = 2) BEGIN
			IF (@ReplicaRole = 2) BEGIN
				IF (@RecoveryHealth = 1) BEGIN
					IF (@SyncState = 2) BEGIN
						/* all conditions met, we can issue failover*/
						SELECT @sql = '' + @crlf +
							'  ALTER AVAILABILITY GROUP [' + @AGName + '] FAILOVER;'+ @crlf
						BEGIN TRY
							EXEC (@sql)
							SELECT @msg = 'Failover command:  ' + @crlf + @sql + 
								@crlf + @crlf + 'Successfully failed over to this replica.'
							SELECT @RetryCount = 0
						END TRY
						BEGIN CATCH
							SELECT @msg = cast(ERROR_NUMBER() as varchar(max)) + 
								' ' + ERROR_MESSAGE()
						END CATCH
					END ELSE BEGIN
						SELECT @msg = 'The synchronization state for this replica is not healthy.  Failover to this node is not possible.'
					END/*sync state*/
				END ELSE BEGIN
					SELECT @msg = 'The recovery health status for this AG is not "online".  This node cannot initiate a failover request.'
				END/*recovery health*/
			END ELSE BEGIN
				SELECT @msg = 'This replica must be a secondary in order to initiate a failover command.'
			END/*replica role*/
		END ELSE BEGIN
			SELECT @msg = 'This replica is not online.  The replica must be online in order to initiate a failover.'
		END /*operational state*/
	END ELSE BEGIN
		SELECT @msg = 'This replica is not in SYNCHRONOUS mode and would require a forced failover to failover to this node.'
	END /*sync mode*/
END ELSE BEGIN
	SELECT @msg ='This replica is not connected with the primary, failover to this node is not possible.'
END/*connected state*/
PRINT @msg



/**************************************************
	If we get here, first attempt was not successful.
	Continue in a retry loop until RetryCount has
	been exhausted, waiting 10 seconds between
	each retry.
	
	Get the states of the replica, AG, & databases.
	Then attempt failover if all pre-reqs are met.
***************************************************/
WHILE @RetryCount > 0 BEGIN
	WAITFOR DELAY '00:00:10';
	SELECT @msg = '';
	SELECT 
		@SyncMode = ars.availability_mode,
		@ReplicaRole = rs.role,
		@OperationalState = rs.operational_state,
		@RecoveryHealth = rs.recovery_health,
		@SyncState = rs.synchronization_health,
		@ConnectedState = rs.connected_state 
		FROM sys.dm_hadr_availability_replica_states rs
		INNER JOIN sys.availability_groups ags
		ON rs.group_id = ags.group_id
		INNER JOIN sys.availability_replicas ars
		on rs.replica_id = ars.replica_id and rs.group_id = ars.group_id		
		WHERE rs.is_local = 1 and ags.name = @AGName;

	IF (@ConnectedState = 1) BEGIN
		IF (@SyncMode = 1) BEGIN
			IF (@OperationalState = 2) BEGIN
				IF (@ReplicaRole = 2) BEGIN
					IF (@RecoveryHealth = 1) BEGIN
						IF (@SyncState = 2) BEGIN
							/* all conditions met, we can issue failover*/
							SELECT @sql = '' + @crlf +
								'  ALTER AVAILABILITY GROUP [' + @AGName + '] FAILOVER;'+ @crlf
							BEGIN TRY
								EXEC (@sql)
								SELECT @msg = 'Failover command:  ' + @crlf + @sql + 
									@crlf + @crlf + 'Successfully failed over to this replica.'
								PRINT @msg
								/*retry attempt successful, break out of while loop*/
								BREAK;
							END TRY
							BEGIN CATCH
								SELECT @msg = cast(ERROR_NUMBER() as varchar(max)) + 
									' ' + ERROR_MESSAGE()
							END CATCH
						END ELSE BEGIN
							SELECT @msg = 'The synchronization state for this replica is not healthy.  Failover to this node is not possible.'
						END/*sync state*/
					END ELSE BEGIN
						SELECT @msg = 'The recovery health status for this AG is not "online".  This node cannot initiate a failover request.'
					END/*recovery health*/
				END ELSE BEGIN
					SELECT @msg = 'This replica must be a secondary in order to initiate a failover command.'
				END/*replica role*/
			END ELSE BEGIN
				SELECT @msg = 'This replica is not online.  The replica must be online in order to initiate a failover.'
			END /*operational state*/
		END ELSE BEGIN
			SELECT @msg = 'This replica is not in SYNCHRONOUS mode and would require a forced failover to failover to this node.'
		END /*sync mode*/
	END ELSE BEGIN
		SELECT @msg ='This replica is not connected with the primary, failover to this node is not possible.'
	END/*connected state*/

SELECT @RetryCount -= 1
PRINT @msg
END/*while*/

THE_END:
