/* this script will obtain the ports defined
 * for each availability group listener that
 * exists.  If no port is defined, it will
 * assign it will use port 1433.
 * The output will show the TSQL syntax
 * to alter the listeners to apply the
 * same port values later, should they 
 * need to be re-configured to the same
 * ports.*/

DECLARE @CRLF CHAR(2) = CHAR(13) + CHAR(10)
DECLARE @EndTryCatch VARCHAR(max) = 'END TRY' + @CRLF +
	'BEGIN CATCH' + @CRLF +
	'IF (@@ERROR <> 19468)' + @CRLF +
	'SELECT ERROR_NUMBER() AS ErrNum, ERROR_MESSAGE() AS ErrMsg' +
	@CRLF + 'END CATCH' + @CRLF

SELECT '-- (1) Copy/Paste the results of this query '
    + ' into a query window.'
	AS [Generated TSQL script:]
UNION
SELECT '-- (2) After all PowerShell scripts/command'
	+ ' have been executed,'
UNION
SELECT '-- (3) Execute the following TSQL commands'
	+ ' to restore PORT settings.'
UNION
SELECT 'BEGIN TRY' + @CRLF + 'ALTER AVAILABILITY GROUP '
	+ ag.name + ' MODIFY LISTENER '''
	+ agl.dns_name + ''' (PORT = '
	+ CAST(ISNULL(agl.port,1433) AS VARCHAR(5)) + ');' 
	+ @CRLF + @EndTryCatch + @CRLF
	FROM sys.availability_group_listeners agl
		INNER JOIN sys.availability_groups ag
		ON agl.group_id = ag.group_id

