SELECT tep.name as EndPointName, sp.name As CreatedBy,tep.type_desc, 
tep.state_desc, tep.port 
	FROM sys.tcp_endpoints tep inner join
	sys.server_principals sp on tep.principal_id = sp.principal_id
	WHERE tep.type = 4


