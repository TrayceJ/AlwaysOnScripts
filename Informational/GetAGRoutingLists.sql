--this query should be run on the Primary for the AG
--It will return all of the the routing lists for this AG (if any exist)
--it will show what the list is for each replica -- for when it acts as primary.

SELECT CAST(ar.replica_server_name as VARCHAR(28)) "When This Server is Primary",
	rl.routing_priority, 
	CAST(ar2.replica_server_name as VARCHAR(20)) "Route to this Server", 
	CAST(ar.secondary_role_allow_connections_desc AS VARCHAR(20)) "Secondary Connection Type",
	CAST(ar2.read_only_routing_url AS VARCHAR(50)) "Routing URL"
	FROM sys.availability_read_only_routing_lists rl
	  inner join sys.availability_replicas ar on rl.replica_id = ar.replica_id
	  inner join sys.availability_replicas ar2 on rl.read_only_replica_id = ar2.replica_id
	ORDER BY ar.replica_server_name, rl.routing_priority
