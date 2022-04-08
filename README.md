# AlwaysOnScripts

Thank you for visiting my collection of scripts and documents relating to the Microsoft SQL Server AlwaysOn Availability Group features.  Many of these scripts were written while I was a member of the AlwaysOn support team in CSS or later as a Premier Field Engineer working at Microsoft.

I have divided up my scripts into three areas (folders):

* BlockedRedoExample
* Diagnostic
* Informational

If you have questions or comments, please feel free to email me at:  trayce.jordan@microsoft.com  or trayce@jordanhome.net.


## BlockedRedoExample

These scripts are designed to demonstrate what REDO blocking is, how it occurs, and how you can detect it.

| File | Description / purpose |
|------|:----------------------|
|BlockRedo_1.sql| Demo script executed on the primary to help demonstrate REDO blocking.|
|BlockRedo_2.sql| Demo script executed on a secondary to help demonstrate REDO blocking.|
|BlockRedo_3.sql| Demo script executed on a secondary to show that the REDO thread is blocked|
|BlockedRedo_showblocker.sql| Another script that shows the offending session that is blocking the REDO thread.|
|Blocked Redo Example.pdf| A set of instructions on how to perform the demonstration.|
## Diagnostic

The scripts in this folder are designed to get information about the health and status of Availability Groups, or to help parse through Extended Event files to help determine root causes for failovers or failure to failover events.

| File | Description / purpose |
|------|:----------------------|
| AGSyncStatus.sql| A script that will return basic information about the status of the AGs.  Can be run on primary or secondary.|
| Get_AOHealth_XEvents.sql| Similar to the shred_AOHealth_XEL.sql file, but designed to run in real-time on a replica node - either primary or secondary.  It parses through the AO Health XEvent files in real-time to look for errors, failover events, blocked REDO events and more.|
| Shred_AOHealth_XEL.sql| Similar to the Get_AOHealth_XEVents.sql file, but designed to run off-line to parse through the AO Health XEvent XEL files from either a primary or secondary.  It parses through the XEL files to look for errors, failover events, blocked REDO events and more.|
|Shred_SQLDIAG_XEL_all.sql| Script that parses through \*SQLDIAG\*.XEL files taken from a primary or secondary.  It returns tables of information retrieved from the files that can be used to look for performance related events, AG state changes, connectivity issues, ring buffer information, IO subsystem issues, and other information that is stored in those XEL files.|
|Shred_system_health_XEL.sql| Script that parses through \*system_health\*.XEL files taken from a primary or secondary.  It returns tables of information retrieved from the files that can be used to look for performance related events, AG state changes, connectivity issues, ring buffer information, IO subsystem issues, and other information that is stored in those XEL files.|
| Files in the _*RedoQueue_Waitinfo*_ folder | The scripts in this folder can be used to troublshoot REDO Queue buildup.  The first script, _*Collect_WaitInfo_for_REDO.sql*_, collects wait info Xevents for about 60 seconds on the REDO & Parallel REDO tasks.  The obtained XEL files can be parsed with the second script, _*Shred_Wait_Info_Xevents.sql*_, to get the top wait types to find out what may be causing REDO activity to lag behind.  For a detailed article on how to collect and interpret the data, please read the following article:  [Troubleshooting REDO queue build-up (data latency issues) on AlwaysOn Readable Secondary Replicas using the WAIT_INFO Extended Event](https://techcommunity.microsoft.com/t5/sql-server-support-blog/troubleshooting-redo-queue-build-up-data-latency-issues-on/ba-p/318488) |

## Informational

The scripts in this folder are some scripts that provide information about the availability groups on a SQL instance.

| File | Description / purpose |
|------|:----------------------|
| AGListener_getports_and_genTSQL.sql| It will list all of the listeners and their ports they listen on, as well as generate a TSQL script that can recreate them if they need to be removed for some reason and re-created.  Often times the port is overlooked.  This helps the administrator re-produce the listener on the same port it was listening on.|
|AGListener_getports.sql| A script to quickly get a list of the Listeners founds and what ports they listen on.|
| AGSyncStatus.sql| A script that will return basic information about the status of the AGs.  Can be run on primary or secondary.|
|Get_HADR_EndPointStates.sql| A script to list the endpoints and their states.  Can be helpful in troubleshooting connectivity issues between the primary and secondary replicas.|
|GetAGRoutingLists.sql| Lists all of the routing lists defined for each availability group on an instance.  Can be helpful in documenting them or troubleshooting failure to be redirected to a secondary replica using read-only routing.|
|WhoIsPrimary.sql| A script that can be run from either a primary or a secondary to tell which node is acting as the primary at that moment.|
