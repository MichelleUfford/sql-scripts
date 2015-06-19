/**********************************************************************************************************

    NAME:           missing.sql

    SYNOPSIS:       Displays potential missing indexes for a given database. Adding the indexes via the
                    provided CREATE scripts may improve server performance. 

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

SELECT 
      t.name AS 'affected_table'
    , 'CREATE NONCLUSTERED INDEX IX_' + t.name + '_missing_'
        + CONVERT(CHAR(8), GETDATE(), 112) + '_'
        + CAST(ROW_NUMBER() OVER (PARTITION BY t.name 
            ORDER BY CAST((ddmigs.user_seeks + ddmigs.user_scans) 
                * ddmigs.avg_user_impact AS BIGINT) DESC) AS VARCHAR(3))
        + ' ON ' + ddmid.statement 
        + ' (' + ISNULL(ddmid.equality_columns,'') 
        + CASE WHEN ddmid.equality_columns IS NOT NULL 
            AND ddmid.inequality_columns IS NOT NULL THEN ',' 
                ELSE '' END 
        + ISNULL(ddmid.inequality_columns, '')
        + ')' 
        + ISNULL(' INCLUDE (' + ddmid.included_columns + ');', ';'
        ) AS sql_statement
    , ddmigs.user_seeks
    , ddmigs.user_scans
    , CAST((ddmigs.user_seeks + ddmigs.user_scans) 
        * ddmigs.avg_user_impact AS BIGINT) AS 'est_impact'
    , ddmigs.last_user_seek
FROM sys.dm_db_missing_index_groups                                 AS ddmig
INNER JOIN sys.dm_db_missing_index_group_stats                      AS ddmigs
    ON ddmigs.group_handle = ddmig.index_group_handle
INNER JOIN sys.dm_db_missing_index_details                          AS ddmid 
    ON ddmig.index_handle = ddmid.index_handle
INNER JOIN sys.tables                                               AS t
    ON ddmid.[object_id] = t.[object_id]
WHERE ddmid.database_id  =  DB_ID()                                                             ----> by default, only examines the current database
  AND CAST((ddmigs.user_seeks + ddmigs.user_scans) * ddmigs.avg_user_impact AS BIGINT)  >  100  ----> 100 is a starting point; update value as appropriate
ORDER BY CAST((ddmigs.user_seeks + ddmigs.user_scans) * ddmigs.avg_user_impact AS BIGINT) DESC;