sql-scripts
===========
Repo for sharing my SQL Server scripts and stored procedures. These are tested on SQL 2005 and 2008; you may need to tweak for 2012 and newer versions. 

# what's available

## admin
* dba_recompile_sp.sql
  * Recompiles all procs in a specific database or all procs; can recompile a specific table, too.
* sql-agent-job-history.sql
  * Explores SQL Agent Job metadata to get job statuses — when the job last ran, when it will run again, an aggregate count of the number of successful and failed executions in the queried time period, T-SQL code to disable the job, etc.

## dev
* bcp_script_generator.sql
  * Generates bcp scripts using SQL Server metadata
* insert_statement_generator.sql
  * Generates insert statements for Teradata using SQL Server metadata. This is useful for easily migrating small tables (i.e. < 1000 rows) from SQL Server to Teradata. DO NOT use on large tables. 
* teradata_ddl_generator.sql
  * Generates Teradata DDL using SQL Server metadata
  
## indexes
* dba_indexDefrag_sp.sql
  * award-winning index defrag script
* dba_indexLookup_sp.sql
  * Retrieves index information for the specified table name.
* dba_indexStats_sp.sql
  * etrieves information regarding indexes; will return drop SQL statement for non-clustered indexes.
* dba_missingIndexStoredProc_sp.sql
  * Retrieves stored procedures with missing indexes in their cached query plans.
* index_definition.sql
  * Displays the definition of indexes; useful to audit indexes across servers & environments
* missing.sql
  * Displays potential missing indexes for a given database. Adding the indexes via the provided CREATE scripts may improve server performance. 
* unused.sql
  *  Displays potential unused indexes for the current database. Dropping these indexes may improve database performance. These statistics are reset each time the server is rebooted, so make sure to review the [sqlserver_start_time] value to ensure the  statistics are captured for a meaningful time period.
  
## misc
* dba_parseString_udf.sql
  * This function parses string input using a variable delimiter.
* dba_viewPageData_sp.sql
  * Retrieves page data for the specified table/page.

## replication
* dba_replicationLatencyGet_sp.sql
  * Retrieves the amount of replication latency in seconds
* dba_replicationLatencyMonitor_sp.sql
  * Stored procedure for retrieving & storing the amount of replication latency in seconds
 
## usage
* dba_findWastedSpace_sp.sql
  * Finds wasted space on a database and/or table
   
# contributing
Contributions are welcome! To contribute a change or enhancement, please issue a pull request for me to review and merge. If you have any questions, I can be reached on Twitter @sqlfool. 
