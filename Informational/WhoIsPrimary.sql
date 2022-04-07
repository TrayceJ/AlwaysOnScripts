--this query (run from any replica) will return who is the Primary Instance
--for each AG.
--If run from a secondary, the secondary must be connected to the primary 
--to return anything useful.
SELECT ags.name as AGName, hags.primary_replica AS PrimaryInstance
FROM sys.dm_hadr_availability_group_states hags
INNER JOIN sys.availability_groups ags 
ON hags.group_id = ags.group_id


--This query provides on a per database if it is the primary replica database.
--additionally the AG to which the database belongs is provided.
--finally the name of the Primary Instance is provided.
SELECT sd.name AS DBName,
    sys.fn_hadr_is_primary_replica(sd.name) AS IsPrimaryReplicaDB, 
    ag.name AS AGName,
    hags.primary_replica AS PrimaryInstance FROM sys.databases sd
    INNER JOIN  sys.availability_replicas ar on sd.replica_id = ar.replica_id
    INNER JOIN sys.availability_groups ag on ar.group_id = ag.group_id
    INNER JOIN sys.dm_hadr_availability_group_states hags on ag.group_id = hags.group_id