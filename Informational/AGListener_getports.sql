/* this script will obtain the ports defined
 * for each availability group listener that
 * exists.*/
 
SELECT ag.name AS [Availability Group],
	agl.dns_name AS [Listener DNS Name],
	agl.port AS [Port]
	FROM sys.availability_group_listeners agl
		INNER JOIN sys.availability_groups ag
		ON agl.group_id = ag.group_id
	ORDER BY ag.name, agl.dns_name
