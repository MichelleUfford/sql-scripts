/**********************************************************************************************************

    NAME:           unused.sql

    SYNOPSIS:       Displays potential unused indexes for the current database. Dropping these indexes 
                    may improve database performance. These statistics are reset each time the server 
                    is rebooted, so make sure to review the [sqlserver_start_time] value to ensure the 
                    statistics are captured for a meaningful time period.

    DEPENDENCIES:   The following dependencies are required to execute this script:
                    - SQL Server 2005 or newer

    AUTHOR:         Michelle Ufford, http://sqlfool.com
    
    CREATED:        2014-04-08
    
    VERSION:        1.0

    LICENSE:        Apache License v2
    
    ----------------------------------------------------------------------------
    DISCLAIMER: 
    This code and information are provided "AS IS" without warranty of any kind,
    either expressed or implied, including but not limited to the implied 
    warranties or merchantability and/or fitness for a particular purpose.
    ----------------------------------------------------------------------------

 ---------------------------------------------------------------------------------------------------------
 --  DATE       VERSION     AUTHOR                  DESCRIPTION                                        --
 ---------------------------------------------------------------------------------------------------------
     20140408   1.0         Michelle Ufford         Open Sourced on GitHub
**********************************************************************************************************/


SELECT sqlserver_start_time FROM sys.dm_os_sys_info;

DECLARE @dbid INT
    , @dbName VARCHAR(100);

SELECT @dbid = DB_ID()
    , @dbName = DB_NAME();

WITH partitionCTE (object_id, index_id, row_count, partition_count) 
AS
(
    SELECT [object_id]
        , index_id
        , SUM([rows]) AS 'row_count'
        , COUNT(partition_id) AS 'partition_count'
    FROM sys.partitions
    GROUP BY [object_id]
        , index_id
)

SELECT OBJECT_NAME(i.[object_id]) AS objectName
        , i.name
        , CASE 
            WHEN i.is_unique = 1 
                THEN 'UNIQUE ' 
            ELSE '' 
          END + i.type_desc AS 'indexType'
        , ddius.user_seeks
        , ddius.user_scans
        , ddius.user_lookups
        , ddius.user_updates
        , cte.row_count
        , CASE WHEN partition_count > 1 THEN 'yes' 
            ELSE 'no' END AS 'partitioned?'
        , CASE 
            WHEN i.type = 2 AND i.is_unique = 0
                THEN 'Drop Index ' + i.name 
                    + ' On ' + @dbName 
                    + '.dbo.' + OBJECT_NAME(ddius.[object_id]) + ';'
            WHEN i.type = 2 AND i.is_unique = 1
                THEN 'Alter Table ' + @dbName 
                    + '.dbo.' + OBJECT_NAME(ddius.[object_ID]) 
                    + ' Drop Constraint ' + i.name + ';'
            ELSE '' 
          END AS 'SQL_DropStatement'
FROM sys.indexes                                                        AS i
INNER JOIN sys.dm_db_index_usage_stats                                  AS ddius
    ON i.object_id = ddius.object_id
        AND i.index_id = ddius.index_id
INNER JOIN partitionCTE                                                 AS cte
    ON i.object_id = cte.object_id
        AND i.index_id = cte.index_id
WHERE ddius.database_id = @dbid
    AND i.type = 2                                                      ----> retrieve nonclustered indexes only
    AND i.is_unique = 0                                                 ----> ignore unique indexes, we'll assume they're serving a necessary business use
    AND (ddius.user_seeks + ddius.user_scans + ddius.user_lookups) = 0  ----> starting point, update this value as needed; 0 retrieves completely unused indexes
ORDER BY user_updates DESC;

