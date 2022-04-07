--BlockRedo_2.sql
--connect to secondary replica database.
--change to the secondary database

USE <dbname>
GO

--execute this query, 
--this should run a good long time before erroring out with an overflow
select sum(cast(a.f1 as float) + cast(b.f1 as float)) from blockredo a
    cross join blockredo b
    cross join blockredo c
    group by a.f1

-- now go to blockredo_3.sql and run query to see the SCH-S locks
-- held by this query.


--at some point in the blockredo_1.sql file you 
--you will be asked to come back to this window 
--and cancel this query.

--after cancelling this query, then go back to blockredo_1.sql
