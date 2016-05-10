/*** Scroll down to the see important notes, disclaimers, and licensing information ***/

/* Let's create our parsing function... */
IF EXISTS ( SELECT  [object_id]
            FROM    sys.objects
            WHERE   name = 'dba_parseString_udf' )
    DROP FUNCTION dbo.dba_parseString_udf;
GO

CREATE FUNCTION dbo.dba_parseString_udf
(
          @stringToParse VARCHAR(8000)  
        , @delimiter     CHAR(1)
)
RETURNS @parsedString TABLE (stringValue VARCHAR(128))
AS
/*********************************************************************************
    Name:       dba_parseString_udf
 
    Author:     Michelle Ufford, http://sqlfool.com
 
    Purpose:    This function parses string input using a variable delimiter.
 
    Notes:      Two common delimiter values are space (' ') and comma (',')
 
    Date        Initials    Description
    ----------------------------------------------------------------------------
    2011-05-20  MFU         Initial Release
*********************************************************************************
Usage: 		
    SELECT *
    FROM dba_parseString_udf(<string>, <delimiter>);
 
Test Cases:
 
    1.  multiple strings separated by space
        SELECT * FROM dbo.dba_parseString_udf('  aaa  bbb  ccc ', ' ');
 
    2.  multiple strings separated by comma
        SELECT * FROM dbo.dba_parseString_udf(',aaa,bbb,,,ccc,', ',');
*********************************************************************************/
BEGIN
 
    /* Declare variables */
    DECLARE @trimmedString  VARCHAR(8000);
 
    /* We need to trim our string input in case the user entered extra spaces */
    SET @trimmedString = LTRIM(RTRIM(@stringToParse));
 
    /* Let's create a recursive CTE to break down our string for us */
    WITH parseCTE (StartPos, EndPos)
    AS
    (
        SELECT 1 AS StartPos
            , CHARINDEX(@delimiter, @trimmedString + @delimiter) AS EndPos
        UNION ALL
        SELECT EndPos + 1 AS StartPos
            , CHARINDEX(@delimiter, @trimmedString + @delimiter , EndPos + 1) AS EndPos
        FROM parseCTE
        WHERE CHARINDEX(@delimiter, @trimmedString + @delimiter, EndPos + 1) <> 0
    )
 
    /* Let's take the results and stick it in a table */  
    INSERT INTO @parsedString
    SELECT SUBSTRING(@trimmedString, StartPos, EndPos - StartPos)
    FROM parseCTE
    WHERE LEN(LTRIM(RTRIM(SUBSTRING(@trimmedString, StartPos, EndPos - StartPos)))) > 0
    OPTION (MaxRecursion 8000);
 
    RETURN;   
END
GO

/* First, we need to take care of schema updates, in case you have a legacy 
   version of the script installed */
DECLARE @indexDefragLog_rename      VARCHAR(128)
  , @indexDefragExclusion_rename    VARCHAR(128)
  , @indexDefragStatus_rename       VARCHAR(128);

SELECT  @indexDefragLog_rename = 'dba_indexDefragLog_obsolete_' + CONVERT(VARCHAR(10), GETDATE(), 112)
      , @indexDefragExclusion_rename = 'dba_indexDefragExclusion_obsolete_' + CONVERT(VARCHAR(10), GETDATE(), 112);

IF EXISTS ( SELECT  [object_id]
            FROM    sys.indexes
            WHERE   name = 'PK_indexDefragLog' ) 
    EXECUTE sp_rename dba_indexDefragLog, @indexDefragLog_rename;

IF EXISTS ( SELECT  [object_id]
            FROM    sys.indexes
            WHERE   name = 'PK_indexDefragExclusion' ) 
    EXECUTE sp_rename dba_indexDefragExclusion, @indexDefragExclusion_rename;

IF NOT EXISTS ( SELECT  [object_id]
                FROM    sys.indexes
                WHERE   name = 'PK_indexDefragLog_v40' )
BEGIN

    CREATE TABLE dbo.dba_indexDefragLog
    (
         indexDefrag_id     INT IDENTITY(1, 1)  NOT NULL
       , databaseID         INT                 NOT NULL
       , databaseName       NVARCHAR(128)       NOT NULL
       , objectID           INT                 NOT NULL
       , objectName         NVARCHAR(128)       NOT NULL
       , indexID            INT                 NOT NULL
       , indexName          NVARCHAR(128)       NOT NULL
       , partitionNumber    SMALLINT            NOT NULL
       , fragmentation      FLOAT               NOT NULL
       , page_count         INT                 NOT NULL
       , dateTimeStart      DATETIME            NOT NULL
       , dateTimeEnd        DATETIME            NULL
       , durationSeconds    INT                 NULL
       , sqlStatement       VARCHAR(4000)       NULL
       , errorMessage       VARCHAR(1000)       NULL 

        CONSTRAINT PK_indexDefragLog_v40 
            PRIMARY KEY CLUSTERED (indexDefrag_id)
    );

    PRINT 'dba_indexDefragLog Table Created';

END

IF NOT EXISTS ( SELECT  [object_id]
                FROM    sys.indexes
                WHERE   name = 'PK_indexDefragExclusion_v40' )
BEGIN

    CREATE TABLE dbo.dba_indexDefragExclusion
    (
         databaseID         INT             NOT NULL
       , databaseName       NVARCHAR(128)   NOT NULL
       , objectID           INT             NOT NULL
       , objectName         NVARCHAR(128)   NOT NULL
       , indexID            INT             NOT NULL
       , indexName          NVARCHAR(128)   NOT NULL
       , exclusionMask      INT             NOT NULL
            /* 1=Sunday, 2=Monday, 4=Tuesday, 8=Wednesday, 16=Thursday, 32=Friday, 64=Saturday */

         CONSTRAINT PK_indexDefragExclusion_v40 
            PRIMARY KEY CLUSTERED (databaseID, objectID, indexID)
    );

    PRINT 'dba_indexDefragExclusion Table Created';

END
                
IF NOT EXISTS ( SELECT  [object_id]
                FROM    sys.indexes
                WHERE   name = 'PK_indexDefragStatus_v40' )
BEGIN

    CREATE TABLE dbo.dba_indexDefragStatus
    (
         databaseID         INT             NOT NULL
       , databaseName       NVARCHAR(128)   NOT NULL
       , objectID           INT             NOT NULL
       , indexID            INT             NOT NULL
       , partitionNumber    SMALLINT        NOT NULL
       , fragmentation      FLOAT           NOT NULL
       , page_count         INT             NOT NULL
       , range_scan_count   BIGINT          NOT NULL
       , schemaName         NVARCHAR(128)   NULL
       , objectName         NVARCHAR(128)   NULL
       , indexName          NVARCHAR(128)   NULL
       , scanDate           DATETIME        NOT NULL
       , defragDate         DATETIME        NULL
       , printStatus        BIT DEFAULT (0) NOT NULL
       , exclusionMask      INT DEFAULT (0) NOT NULL
    
        CONSTRAINT PK_indexDefragStatus_v40 
            PRIMARY KEY CLUSTERED (databaseID, objectID, indexID, partitionNumber)
    );

    PRINT 'dba_indexDefragStatus Table Created';

END;

IF OBJECTPROPERTY(OBJECT_ID('dbo.dba_indexDefrag_sp'), N'IsProcedure') = 1 
    BEGIN
        DROP PROCEDURE dbo.dba_indexDefrag_sp;
        PRINT 'Procedure dba_indexDefrag_sp dropped';
    END;
Go

CREATE PROCEDURE dbo.dba_indexDefrag_sp

    /* Declare Parameters */
    @minFragmentation       FLOAT               = 10.0  
        /* in percent, will not defrag if fragmentation less than specified */
  , @rebuildThreshold       FLOAT               = 30.0  
        /* in percent, greater than @rebuildThreshold will result in rebuild instead of reorg */
  , @executeSQL             BIT                 = 1     
        /* 1 = execute; 0 = print command only */
  , @defragOrderColumn      NVARCHAR(20)        = 'range_scan_count'
        /* Valid options are: range_scan_count, fragmentation, page_count */
  , @defragSortOrder        NVARCHAR(4)         = 'DESC'
        /* Valid options are: ASC, DESC */
  , @timeLimit              INT                 = 720 /* defaulted to 12 hours */
        /* Optional time limitation; expressed in minutes */
  , @database               VARCHAR(128)        = NULL
        /* Option to specify one or more database names, separated by commas; NULL will return all */
  , @tableName              VARCHAR(4000)       = NULL  -- databaseName.schema.tableName
        /* Option to specify a table name; null will return all */
  , @forceRescan            BIT                 = 0
        /* Whether or not to force a rescan of indexes; 1 = force, 0 = use existing scan, if available */
  , @scanMode               VARCHAR(10)         = N'LIMITED'
        /* Options are LIMITED, SAMPLED, and DETAILED */
  , @minPageCount           INT                 = 8 
        /*  MS recommends > 1 extent (8 pages) */
  , @maxPageCount           INT                 = NULL
        /* NULL = no limit */
  , @excludeMaxPartition    BIT                 = 0
        /* 1 = exclude right-most populated partition; 0 = do not exclude; see notes for caveats */
  , @onlineRebuild          BIT                 = 1     
        /* 1 = online rebuild; 0 = offline rebuild; only in Enterprise */
  , @sortInTempDB           BIT                 = 1
        /* 1 = perform sort operation in TempDB; 0 = perform sort operation in the index's database */
  , @maxDopRestriction      TINYINT             = NULL
        /* Option to restrict the number of processors for the operation; only in Enterprise */
  , @printCommands          BIT                 = 0     
        /* 1 = print commands; 0 = do not print commands */
  , @printFragmentation     BIT                 = 0
        /* 1 = print fragmentation prior to defrag; 
           0 = do not print */
  , @defragDelay            CHAR(8)             = '00:00:05'
        /* time to wait between defrag commands */
  , @debugMode              BIT                 = 0
        /* display some useful comments to help determine if/WHERE issues occur */
AS /*********************************************************************************
    Name:       dba_indexDefrag_sp

    Author:     Michelle Ufford, http://sqlfool.com

    Purpose:    Defrags one or more indexes for one or more databases

    Notes:

    CAUTION: TRANSACTION LOG SIZE SHOULD BE MONITORED CLOSELY WHEN DEFRAGMENTING.
             DO NOT RUN UNATTENDED ON LARGE DATABASES DURING BUSINESS HOURS.

      @minFragmentation     defaulted to 10%, will not defrag if fragmentation 
                            is less than that
      
      @rebuildThreshold     defaulted to 30% AS recommended by Microsoft in BOL;
                            greater than 30% will result in rebuild instead

      @executeSQL           1 = execute the SQL generated by this proc; 
                            0 = print command only

      @defragOrderColumn    Defines how to prioritize the order of defrags.  Only
                            used if @executeSQL = 1.  
                            Valid options are: 
                            range_scan_count = count of range and table scans on the
                                               index; in general, this is what benefits 
                                               the most FROM defragmentation
                            fragmentation    = amount of fragmentation in the index;
                                               the higher the number, the worse it is
                            page_count       = number of pages in the index; affects
                                               how long it takes to defrag an index

      @defragSortOrder      The sort order of the ORDER BY clause.
                            Valid options are ASC (ascending) or DESC (descending).

      @timeLimit            Optional, limits how much time can be spent performing 
                            index defrags; expressed in minutes.

                            NOTE: The time limit is checked BEFORE an index defrag
                                  is begun, thus a long index defrag can exceed the
                                  time limitation.

      @database             Optional, specify specific database name to defrag;
                            If not specified, all non-system databases will
                            be defragged.

      @tableName            Specify if you only want to defrag indexes for a 
                            specific table, format = databaseName.schema.tableName;
                            if not specified, all tables will be defragged.

      @forceRescan          Whether or not to force a rescan of indexes.  If set
                            to 0, a rescan will not occur until all indexes have
                            been defragged.  This can span multiple executions.
                            1 = force a rescan
                            0 = use previous scan, if there are indexes left to defrag

      @scanMode             Specifies which scan mode to use to determine
                            fragmentation levels.  Options are:
                            LIMITED - scans the parent level; quickest mode,
                                      recommended for most cases.
                            SAMPLED - samples 1% of all data pages; if less than
                                      10k pages, performs a DETAILED scan.
                            DETAILED - scans all data pages.  Use great care with
                                       this mode, AS it can cause performance issues.

      @minPageCount         Specifies how many pages must exist in an index in order 
                            to be considered for a defrag.  Defaulted to 8 pages, AS 
                            Microsoft recommends only defragging indexes with more 
                            than 1 extent (8 pages).  

                            NOTE: The @minPageCount will restrict the indexes that
                            are stored in dba_indexDefragStatus table.

      @maxPageCount         Specifies the maximum number of pages that can exist in 
                            an index and still be considered for a defrag.  Useful
                            for scheduling small indexes during business hours and
                            large indexes for non-business hours.

                            NOTE: The @maxPageCount will restrict the indexes that
                            are defragged during the current operation; it will not
                            prevent indexes FROM being stored in the 
                            dba_indexDefragStatus table.  This way, a single scan
                            can support multiple page count thresholds.

      @excludeMaxPartition  If an index is partitioned, this option specifies whether
                            to exclude the right-most populated partition.  Typically,
                            this is the partition that is currently being written to in
                            a sliding-window scenario.  Enabling this feature may reduce
                            contention.  This may not be applicable in other types of 
                            partitioning scenarios.  Non-partitioned indexes are 
                            unaffected by this option.
                            1 = exclude right-most populated partition
                            0 = do not exclude

      @onlineRebuild        1 = online rebuild; 
                            0 = offline rebuild

      @sortInTempDB         Specifies whether to defrag the index in TEMPDB or in the
                            database the index belongs to.  Enabling this option may
                            result in faster defrags and prevent database file size 
                            inflation.
                            1 = perform sort operation in TempDB
                            0 = perform sort operation in the index's database 

      @maxDopRestriction    Option to specify a processor limit for index rebuilds

      @printCommands        1 = print commands to screen; 
                            0 = do not print commands

      @printFragmentation   1 = print fragmentation to screen;
                            0 = do not print fragmentation

      @defragDelay          Time to wait between defrag commands; gives the
                            server a little time to catch up 

      @debugMode            1 = display debug comments; helps with troubleshooting
                            0 = do not display debug comments

    Called by:  SQL Agent Job or DBA

    ----------------------------------------------------------------------------
    DISCLAIMER: 
    This code and information are provided "AS IS" without warranty of any kind,
    either expressed or implied, including but not limited to the implied 
    warranties or merchantability and/or fitness for a particular purpose.
    ----------------------------------------------------------------------------
    LICENSE: 
    This index defrag script is free to download and use for personal, educational, 
    and internal corporate purposes, provided that this header is preserved. 
    Redistribution or sale of this index defrag script, in whole or in part, is 
    prohibited without the author's express written consent.
    ----------------------------------------------------------------------------
    Date        Initials	Version Description
    ----------------------------------------------------------------------------
    2007-12-18  MFU         1.0     Initial Release
    2008-10-17  MFU         1.1     Added @defragDelay, CIX_temp_indexDefragList
    2008-11-17  MFU         1.2     Added page_count to log table
                                    , added @printFragmentation option
    2009-03-17  MFU         2.0     Provided support for centralized execution
                                    , consolidated Enterprise & Standard versions
                                    , added @debugMode, @maxDopRestriction
                                    , modified LOB and partition logic  
    2009-06-18  MFU         3.0     Fixed bug in LOB logic, added @scanMode option
                                    , added support for stat rebuilds (@rebuildStats)
                                    , support model and msdb defrag
                                    , added columns to the dba_indexDefragLog table
                                    , modified logging to show "in progress" defrags
                                    , added defrag exclusion list (scheduling)
    2009-08-28  MFU         3.1     Fixed read_only bug for database lists
    2010-04-20  MFU         4.0     Added time limit option
                                    , added static table with rescan logic
                                    , added parameters for page count & SORT_IN_TEMPDB
                                    , added try/catch logic and additional debug options
                                    , added options for defrag prioritization
                                    , fixed bug for indexes with allow_page_lock = off
                                    , added option to exclude right-most partition
                                    , removed @rebuildStats option
                                    , refer to http://sqlfool.com for full release notes
    2011-04-28  MFU         4.1     Bug fixes for databases requiring []
                                    , cleaned up the create table section
                                    , updated syntax for case-sensitive databases
                                    , comma-delimited list for @database now supported
*********************************************************************************
    Example of how to call this script:

        EXECUTE dbo.dba_indexDefrag_sp
              @executeSQL           = 1
            , @printCommands        = 1
            , @debugMode            = 1
            , @printFragmentation   = 1
            , @forceRescan          = 1
            , @maxDopRestriction    = 1
            , @minPageCount         = 8
            , @maxPageCount         = NULL
            , @minFragmentation     = 1
            , @rebuildThreshold     = 30
            , @defragDelay          = '00:00:05'
            , @defragOrderColumn    = 'page_count'
            , @defragSortOrder      = 'DESC'
            , @excludeMaxPartition  = 1
            , @timeLimit            = NULL
            , @database             = 'sandbox,sandbox_caseSensitive';
*********************************************************************************/																
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

BEGIN

    BEGIN TRY

        /* Just a little validation... */
        IF @minFragmentation IS NULL 
            OR @minFragmentation NOT BETWEEN 0.00 AND 100.0
                SET @minFragmentation = 10.0;

        IF @rebuildThreshold IS NULL
            OR @rebuildThreshold NOT BETWEEN 0.00 AND 100.0
                SET @rebuildThreshold = 30.0;

        IF @defragDelay NOT LIKE '00:[0-5][0-9]:[0-5][0-9]'
            SET @defragDelay = '00:00:05';

        IF @defragOrderColumn IS NULL
            OR @defragOrderColumn NOT IN ('range_scan_count', 'fragmentation', 'page_count')
                SET @defragOrderColumn = 'range_scan_count';

        IF @defragSortOrder IS NULL
            OR @defragSortOrder NOT IN ('ASC', 'DESC')
                SET @defragSortOrder = 'DESC';

        IF @scanMode NOT IN ('LIMITED', 'SAMPLED', 'DETAILED')
            SET @scanMode = 'LIMITED';

        IF @executeSQL IS NULL
            SET @executeSQL = 0;

        IF @debugMode IS NULL
            SET @debugMode = 0;

        IF @forceRescan IS NULL
            SET @forceRescan = 0;
            
        IF @minPageCount IS NULL
            SET @minPageCount = 8;

        IF @sortInTempDB IS NULL
            SET @sortInTempDB = 1;

        IF @onlineRebuild IS NULL
            SET @onlineRebuild = 0;

        IF @debugMode = 1 RAISERROR('Undusting the cogs AND starting up...', 0, 42) WITH NOWAIT;

        /* Declare our variables */
        DECLARE   @objectID                 INT
                , @databaseID               INT
                , @databaseName             NVARCHAR(128)
                , @indexID                  INT
                , @partitionCount           BIGINT
                , @schemaName               NVARCHAR(128)
                , @objectName               NVARCHAR(128)
                , @indexName                NVARCHAR(128)
                , @partitionNumber          SMALLINT
                , @fragmentation            FLOAT
                , @pageCount                INT
                , @sqlCommand               NVARCHAR(4000)
                , @rebuildCommand           NVARCHAR(200)
                , @datetimestart            DATETIME
                , @dateTimeEnd              DATETIME
                , @containsLOB              BIT
                , @editionCheck             BIT
                , @debugMessage             NVARCHAR(4000)
                , @updateSQL                NVARCHAR(4000)
                , @partitionSQL             NVARCHAR(4000)
                , @partitionSQL_Param       NVARCHAR(1000)
                , @LOB_SQL                  NVARCHAR(4000)
                , @LOB_SQL_Param            NVARCHAR(1000)
                , @indexDefrag_id           INT
                , @startdatetime            DATETIME
                , @enddatetime              DATETIME
                , @getIndexSQL              NVARCHAR(4000)
                , @getIndexSQL_Param        NVARCHAR(4000)
                , @allowPageLockSQL         NVARCHAR(4000)
                , @allowPageLockSQL_Param   NVARCHAR(4000)
                , @allowPageLocks           INT
                , @excludeMaxPartitionSQL   NVARCHAR(4000);

        /* Initialize our variables */
        SELECT @startdatetime = GETDATE()
            , @enddatetime = DATEADD(minute, @timeLimit, GETDATE());

        /* Create our temporary tables */
        CREATE TABLE #databaseList
        (
              databaseID        INT
            , databaseName      VARCHAR(128)
            , scanStatus        BIT
        );

        CREATE TABLE #processor 
        (
              [index]           INT
            , Name              VARCHAR(128)
            , Internal_Value    INT
            , Character_Value   INT
        );

        CREATE TABLE #maxPartitionList
        (
              databaseID        INT
            , objectID          INT
            , indexID           INT
            , maxPartition      INT
        );

        IF @debugMode = 1 RAISERROR('Beginning validation...', 0, 42) WITH NOWAIT;

        /* Make sure we're not exceeding the number of processors we have available */
        INSERT INTO #processor
        EXECUTE xp_msver 'ProcessorCount';

        IF @maxDopRestriction IS NOT NULL AND @maxDopRestriction > (SELECT Internal_Value FROM #processor)
            SELECT @maxDopRestriction = Internal_Value
            FROM #processor;

        /* Check our server version; 1804890536 = Enterprise, 610778273 = Enterprise Evaluation, -2117995310 = Developer */
        IF (SELECT ServerProperty('EditionID')) IN (1804890536, 610778273, -2117995310) 
            SET @editionCheck = 1 -- supports online rebuilds
        ELSE
            SET @editionCheck = 0; -- does not support online rebuilds

        /* Output the parameters we're working with */
        IF @debugMode = 1 
        BEGIN

            SELECT @debugMessage = 'Your SELECTed parameters are... 
            Defrag indexes WITH fragmentation greater than ' + CAST(@minFragmentation AS VARCHAR(10)) + ';
            REBUILD indexes WITH fragmentation greater than ' + CAST(@rebuildThreshold AS VARCHAR(10)) + ';
            You' + CASE WHEN @executeSQL = 1 THEN ' DO' ELSE ' DO NOT' END + ' want the commands to be executed automatically; 
            You want to defrag indexes in ' + @defragSortOrder + ' order of the ' + UPPER(@defragOrderColumn) + ' value;
            You have' + CASE WHEN @timeLimit IS NULL THEN ' NOT specified a time limit;' ELSE ' specified a time limit of ' 
                + CAST(@timeLimit AS VARCHAR(10)) END + ' minutes;
            ' + CASE WHEN @database IS NULL THEN 'ALL databases' ELSE 'The ' + @database + ' database(s)' END + ' will be defragged;
            ' + CASE WHEN @tableName IS NULL THEN 'ALL tables' ELSE 'The ' + @tableName + ' TABLE' END + ' will be defragged;
            We' + CASE WHEN EXISTS(SELECT Top 1 * FROM dbo.dba_indexDefragStatus WHERE defragDate IS NULL)
                AND @forceRescan <> 1 THEN ' WILL NOT' ELSE ' WILL' END + ' be rescanning indexes;
            The scan will be performed in ' + @scanMode + ' mode;
            You want to limit defrags to indexes with' + CASE WHEN @maxPageCount IS NULL THEN ' more than ' 
                + CAST(@minPageCount AS VARCHAR(10)) ELSE
                ' BETWEEN ' + CAST(@minPageCount AS VARCHAR(10))
                + ' AND ' + CAST(@maxPageCount AS VARCHAR(10)) END + ' pages;
            Indexes will be defragged' + CASE WHEN @editionCheck = 0 OR @onlineRebuild = 0 THEN ' OFFLINE;' ELSE ' ONLINE;' END + '
            Indexes will be sorted in' + CASE WHEN @sortInTempDB = 0 THEN ' the DATABASE' ELSE ' TEMPDB;' END + '
            Defrag operations will utilize ' + CASE WHEN @editionCheck = 0 OR @maxDopRestriction IS NULL 
                THEN 'system defaults for processors;' 
                ELSE CAST(@maxDopRestriction AS VARCHAR(2)) + ' processors;' END + '
            You' + CASE WHEN @printCommands = 1 THEN ' DO' ELSE ' DO NOT' END + ' want to PRINT the ALTER INDEX commands; 
            You' + CASE WHEN @printFragmentation = 1 THEN ' DO' ELSE ' DO NOT' END + ' want to OUTPUT fragmentation levels; 
            You want to wait ' + @defragDelay + ' (hh:mm:ss) BETWEEN defragging indexes;
            You want to run in' + CASE WHEN @debugMode = 1 THEN ' DEBUG' ELSE ' SILENT' END + ' mode.';

            RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
        
        END;

        IF @debugMode = 1 RAISERROR('Grabbing a list of our databases...', 0, 42) WITH NOWAIT;

        /* Retrieve the list of databases to investigate */
        /* If @database is NULL, it means we want to defrag *all* databases */
        IF @database IS NULL
        BEGIN

            INSERT INTO #databaseList
            SELECT database_id
                , name
                , 0 -- not scanned yet for fragmentation
            FROM sys.databases
            WHERE [name] NOT IN ('master', 'tempdb')-- exclude system databases
                AND [state] = 0 -- state must be ONLINE
                AND is_read_only = 0;  -- cannot be read_only

        END;
        ELSE
        /* Otherwise, we're going to just defrag our list of databases */
        BEGIN

            INSERT INTO #databaseList
            SELECT database_id
                , name
                , 0 -- not scanned yet for fragmentation
            FROM sys.databases AS d
            JOIN dbo.dba_parseString_udf(@database, ',') AS x
                ON d.name COLLATE database_default = x.stringValue
            WHERE [name] NOT IN ('master', 'tempdb')-- exclude system databases
                AND [state] = 0 -- state must be ONLINE
                AND is_read_only = 0;  -- cannot be read_only

        END; 

        /* Check to see IF we have indexes in need of defrag; otherwise, re-scan the database(s) */
        IF NOT EXISTS(SELECT Top 1 * FROM dbo.dba_indexDefragStatus WHERE defragDate IS NULL)
            OR @forceRescan = 1
        BEGIN

            /* Truncate our list of indexes to prepare for a new scan */
            TRUNCATE TABLE dbo.dba_indexDefragStatus;

            IF @debugMode = 1 RAISERROR('Looping through our list of databases and checking for fragmentation...', 0, 42) WITH NOWAIT;

            /* Loop through our list of databases */
            WHILE (SELECT COUNT(*) FROM #databaseList WHERE scanStatus = 0) > 0
            BEGIN

                SELECT Top 1 @databaseID = databaseID
                FROM #databaseList
                WHERE scanStatus = 0;

                SELECT @debugMessage = '  working on ' + DB_NAME(@databaseID) + '...';

                IF @debugMode = 1
                    RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;

               /* Determine which indexes to defrag using our user-defined parameters */
                INSERT INTO dbo.dba_indexDefragStatus
                (
                      databaseID
                    , databaseName
                    , objectID
                    , indexID
                    , partitionNumber
                    , fragmentation
                    , page_count
                    , range_scan_count
                    , scanDate
                )
                SELECT
                      ps.database_id AS 'databaseID'
                    , QUOTENAME(DB_NAME(ps.database_id)) AS 'databaseName'
                    , ps.[object_id] AS 'objectID'
                    , ps.index_id AS 'indexID'
                    , ps.partition_number AS 'partitionNumber'
                    , SUM(ps.avg_fragmentation_in_percent) AS 'fragmentation'
                    , SUM(ps.page_count) AS 'page_count'
                    , os.range_scan_count
                    , GETDATE() AS 'scanDate'
                FROM sys.dm_db_index_physical_stats(@databaseID, OBJECT_ID(@tableName), NULL , NULL, @scanMode) AS ps
                JOIN sys.dm_db_index_operational_stats(@databaseID, OBJECT_ID(@tableName), NULL , NULL) AS os
                    ON ps.database_id = os.database_id
                    AND ps.[object_id] = os.[object_id]
                    AND ps.index_id = os.index_id
                    AND ps.partition_number = os.partition_number
                WHERE avg_fragmentation_in_percent >= @minFragmentation 
                    AND ps.index_id > 0 -- ignore heaps
                    AND ps.page_count > @minPageCount 
                    AND ps.index_level = 0 -- leaf-level nodes only, supports @scanMode
                GROUP BY ps.database_id 
                    , QUOTENAME(DB_NAME(ps.database_id)) 
                    , ps.[object_id]
                    , ps.index_id 
                    , ps.partition_number 
                    , os.range_scan_count
                OPTION (MAXDOP 2);

                /* Do we want to exclude right-most populated partition of our partitioned indexes? */
                IF @excludeMaxPartition = 1
                BEGIN

                    SET @excludeMaxPartitionSQL = '
                        SELECT ' + CAST(@databaseID AS VARCHAR(10)) + ' AS [databaseID]
                            , [object_id]
                            , index_id
                            , MAX(partition_number) AS [maxPartition]
                        FROM [' + DB_NAME(@databaseID) + '].sys.partitions
                        WHERE partition_number > 1
                            AND [rows] > 0
                        GROUP BY object_id
                            , index_id;';

                    INSERT INTO #maxPartitionList
                    EXECUTE sp_executesql @excludeMaxPartitionSQL;

                END;
                
                /* Keep track of which databases have already been scanned */
                UPDATE #databaseList
                SET scanStatus = 1
                WHERE databaseID = @databaseID;

            END

            /* We don't want to defrag the right-most populated partition, so
               delete any records for partitioned indexes where partition = MAX(partition) */
            IF @excludeMaxPartition = 1
            BEGIN

                DELETE ids
                FROM dbo.dba_indexDefragStatus AS ids
                JOIN #maxPartitionList AS mpl
                    ON ids.databaseID = mpl.databaseID
                    AND ids.objectID = mpl.objectID
                    AND ids.indexID = mpl.indexID
                    AND ids.partitionNumber = mpl.maxPartition;

            END;

            /* Update our exclusion mask for any index that has a restriction ON the days it can be defragged */
            UPDATE ids
            SET ids.exclusionMask = ide.exclusionMask
            FROM dbo.dba_indexDefragStatus AS ids
            JOIN dbo.dba_indexDefragExclusion AS ide
                ON ids.databaseID = ide.databaseID
                AND ids.objectID = ide.objectID
                AND ids.indexID = ide.indexID;
         
        END

        SELECT @debugMessage = 'Looping through our list... there are ' + CAST(COUNT(*) AS VARCHAR(10)) + ' indexes to defrag!'
        FROM dbo.dba_indexDefragStatus
        WHERE defragDate IS NULL
            AND page_count BETWEEN @minPageCount AND ISNULL(@maxPageCount, page_count);

        IF @debugMode = 1 RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;

        /* Begin our loop for defragging */
        WHILE (SELECT COUNT(*) 
               FROM dbo.dba_indexDefragStatus 
               WHERE (
                           (@executeSQL = 1 AND defragDate IS NULL) 
                        OR (@executeSQL = 0 AND defragDate IS NULL AND printStatus = 0)
                     )
                AND exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0
                AND page_count BETWEEN @minPageCount AND ISNULL(@maxPageCount, page_count)) > 0
        BEGIN

            /* Check to see IF we need to exit our loop because of our time limit */        
            IF ISNULL(@enddatetime, GETDATE()) < GETDATE()
            BEGIN
                RAISERROR('Our time limit has been exceeded!', 11, 42) WITH NOWAIT;
            END;

            IF @debugMode = 1 RAISERROR('  Picking an index to beat into shape...', 0, 42) WITH NOWAIT;

            /* Grab the index with the highest priority, based on the values submitted; 
               Look at the exclusion mask to ensure it can be defragged today */
            SET @getIndexSQL = N'
            SELECT TOP 1 
                  @objectID_Out         = objectID
                , @indexID_Out          = indexID
                , @databaseID_Out       = databaseID
                , @databaseName_Out     = databaseName
                , @fragmentation_Out    = fragmentation
                , @partitionNumber_Out  = partitionNumber
                , @pageCount_Out        = page_count
            FROM dbo.dba_indexDefragStatus
            WHERE defragDate IS NULL ' 
                + CASE WHEN @executeSQL = 0 THEN 'AND printStatus = 0' ELSE '' END + '
                AND exclusionMask & Power(2, DatePart(weekday, GETDATE())-1) = 0
                AND page_count BETWEEN @p_minPageCount AND ISNULL(@p_maxPageCount, page_count)
            ORDER BY + ' + @defragOrderColumn + ' ' + @defragSortOrder;
                       
            SET @getIndexSQL_Param = N'@objectID_Out        INT OUTPUT
                                     , @indexID_Out         INT OUTPUT
                                     , @databaseID_Out      INT OUTPUT
                                     , @databaseName_Out    NVARCHAR(128) OUTPUT
                                     , @fragmentation_Out   INT OUTPUT
                                     , @partitionNumber_Out INT OUTPUT
                                     , @pageCount_Out       INT OUTPUT
                                     , @p_minPageCount      INT
                                     , @p_maxPageCount      INT';

            EXECUTE sp_executesql @getIndexSQL
                , @getIndexSQL_Param
                , @p_minPageCount       = @minPageCount
                , @p_maxPageCount       = @maxPageCount
                , @objectID_Out         = @objectID         OUTPUT
                , @indexID_Out          = @indexID          OUTPUT
                , @databaseID_Out       = @databaseID       OUTPUT
                , @databaseName_Out     = @databaseName     OUTPUT
                , @fragmentation_Out    = @fragmentation    OUTPUT
                , @partitionNumber_Out  = @partitionNumber  OUTPUT
                , @pageCount_Out        = @pageCount        OUTPUT;

            IF @debugMode = 1 RAISERROR('  Looking up the specifics for our index...', 0, 42) WITH NOWAIT;

            /* Look up index information */
            SELECT @updateSQL = N'UPDATE ids
                SET schemaName = QUOTENAME(s.name)
                    , objectName = QUOTENAME(o.name)
                    , indexName = QUOTENAME(i.name)
                FROM dbo.dba_indexDefragStatus AS ids
                INNER JOIN ' + @databaseName + '.sys.objects AS o
                    ON ids.objectID = o.[object_id]
                INNER JOIN ' + @databaseName + '.sys.indexes AS i
                    ON o.[object_id] = i.[object_id]
                    AND ids.indexID = i.index_id
                INNER JOIN ' + @databaseName + '.sys.schemas AS s
                    ON o.schema_id = s.schema_id
                WHERE o.[object_id] = ' + CAST(@objectID AS VARCHAR(10)) + '
                    AND i.index_id = ' + CAST(@indexID AS VARCHAR(10)) + '
                    AND i.type > 0
                    AND ids.databaseID = ' + CAST(@databaseID AS VARCHAR(10));

            EXECUTE sp_executesql @updateSQL;

            /* Grab our object names */
            SELECT @objectName  = objectName
                , @schemaName   = schemaName
                , @indexName    = indexName
            FROM dbo.dba_indexDefragStatus
            WHERE objectID = @objectID
                AND indexID = @indexID
                AND databaseID = @databaseID;

            IF @debugMode = 1 RAISERROR('  Grabbing the partition COUNT...', 0, 42) WITH NOWAIT;

            /* Determine if the index is partitioned */
            SELECT @partitionSQL = 'SELECT @partitionCount_OUT = COUNT(*)
                                        FROM ' + @databaseName + '.sys.partitions
                                        WHERE object_id = ' + CAST(@objectID AS VARCHAR(10)) + '
                                            AND index_id = ' + CAST(@indexID AS VARCHAR(10)) + ';'
                , @partitionSQL_Param = '@partitionCount_OUT INT OUTPUT';

            EXECUTE sp_executesql @partitionSQL, @partitionSQL_Param, @partitionCount_OUT = @partitionCount OUTPUT;

            IF @debugMode = 1 RAISERROR('  Seeing IF there are any LOBs to be handled...', 0, 42) WITH NOWAIT;
        
            /* Determine if the table contains LOBs */
            SELECT @LOB_SQL = ' SELECT @containsLOB_OUT = COUNT(*)
                                FROM ' + @databaseName + '.sys.columns WITH (NoLock) 
                                WHERE [object_id] = ' + CAST(@objectID AS VARCHAR(10)) + '
                                   AND (system_type_id IN (34, 35, 99)
                                            OR max_length = -1);'
                                /*  system_type_id --> 34 = IMAGE, 35 = TEXT, 99 = NTEXT
                                    max_length = -1 --> VARBINARY(MAX), VARCHAR(MAX), NVARCHAR(MAX), XML */
                    , @LOB_SQL_Param = '@containsLOB_OUT INT OUTPUT';

            EXECUTE sp_executesql @LOB_SQL, @LOB_SQL_Param, @containsLOB_OUT = @containsLOB OUTPUT;

            IF @debugMode = 1 RAISERROR('  Checking for indexes that do NOT allow page locks...', 0, 42) WITH NOWAIT;

            /* Determine if page locks are allowed; for those indexes, we need to always REBUILD */
            SELECT @allowPageLockSQL = 'SELECT @allowPageLocks_OUT = COUNT(*)
                                        FROM ' + @databaseName + '.sys.indexes
                                        WHERE object_id = ' + CAST(@objectID AS VARCHAR(10)) + '
                                            AND index_id = ' + CAST(@indexID AS VARCHAR(10)) + '
                                            AND Allow_Page_Locks = 0;'
                , @allowPageLockSQL_Param = '@allowPageLocks_OUT INT OUTPUT';

            EXECUTE sp_executesql @allowPageLockSQL, @allowPageLockSQL_Param, @allowPageLocks_OUT = @allowPageLocks OUTPUT;

            IF @debugMode = 1 RAISERROR('  Building our SQL statements...', 0, 42) WITH NOWAIT;

            /* IF there's not a lot of fragmentation, or if we have a LOB, we should REORGANIZE */
            IF (@fragmentation < @rebuildThreshold OR @containsLOB >= 1 OR @partitionCount > 1)
                AND @allowPageLocks = 0
            BEGIN
            
                SET @sqlCommand = N'ALTER INDEX ' + @indexName + N' ON ' + @databaseName + N'.' 
                                    + @schemaName + N'.' + @objectName + N' REORGANIZE';

                /* If our index is partitioned, we should always REORGANIZE */
                IF @partitionCount > 1
                    SET @sqlCommand = @sqlCommand + N' PARTITION = ' 
                                    + CAST(@partitionNumber AS NVARCHAR(10));

            END
            /* If the index is heavily fragmented and doesn't contain any partitions or LOB's, 
               or if the index does not allow page locks, REBUILD it */
            ELSE IF (@fragmentation >= @rebuildThreshold OR @allowPageLocks <> 0)
                AND ISNULL(@containsLOB, 0) != 1 AND @partitionCount <= 1
            BEGIN

                /* Set online REBUILD options; requires Enterprise Edition */
                IF @onlineRebuild = 1 AND @editionCheck = 1 
                    SET @rebuildCommand = N' REBUILD WITH (ONLINE = ON';
                ELSE
                    SET @rebuildCommand = N' REBUILD WITH (ONLINE = Off';
                
                /* Set sort operation preferences */
                IF @sortInTempDB = 1 
                    SET @rebuildCommand = @rebuildCommand + N', SORT_IN_TEMPDB = ON';
                ELSE
                    SET @rebuildCommand = @rebuildCommand + N', SORT_IN_TEMPDB = Off';

                /* Set processor restriction options; requires Enterprise Edition */
                IF @maxDopRestriction IS NOT NULL AND @editionCheck = 1
                    SET @rebuildCommand = @rebuildCommand + N', MAXDOP = ' + CAST(@maxDopRestriction AS VARCHAR(2)) + N')';
                ELSE
                    SET @rebuildCommand = @rebuildCommand + N')';

                SET @sqlCommand = N'ALTER INDEX ' + @indexName + N' ON ' + @databaseName + N'.'
                                + @schemaName + N'.' + @objectName + @rebuildCommand;

            END
            ELSE
                /* Print an error message if any indexes happen to not meet the criteria above */
                IF @printCommands = 1 OR @debugMode = 1
                    RAISERROR('We are unable to defrag this index.', 0, 42) WITH NOWAIT;

            /* Are we executing the SQL?  IF so, do it */
            IF @executeSQL = 1
            BEGIN

                SET @debugMessage = 'Executing: ' + @sqlCommand;
                
                /* Print the commands we're executing if specified to do so */
                IF @printCommands = 1 OR @debugMode = 1
                    RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;

                /* Grab the time for logging purposes */
                SET @datetimestart  = GETDATE();

                /* Log our actions */
                INSERT INTO dbo.dba_indexDefragLog
                (
                      databaseID
                    , databaseName
                    , objectID
                    , objectName
                    , indexID
                    , indexName
                    , partitionNumber
                    , fragmentation
                    , page_count
                    , dateTimeStart
                    , sqlStatement
                )
                SELECT
                      @databaseID
                    , @databaseName
                    , @objectID
                    , @objectName
                    , @indexID
                    , @indexName
                    , @partitionNumber
                    , @fragmentation
                    , @pageCount
                    , @datetimestart
                    , @sqlCommand;

                SET @indexDefrag_id = SCOPE_IDENTITY();

                /* Wrap our execution attempt in a TRY/CATCH and log any errors that occur */
                BEGIN TRY

                    /* Execute our defrag! */
                    EXECUTE sp_executesql @sqlCommand;
                    SET @dateTimeEnd = GETDATE();
                    
                    /* Update our log with our completion time */
                    UPDATE dbo.dba_indexDefragLog
                    SET dateTimeEnd = @dateTimeEnd
                        , durationSeconds = DATEDIFF(second, @datetimestart, @dateTimeEnd)
                    WHERE indexDefrag_id = @indexDefrag_id;

                END TRY
                BEGIN CATCH

                    /* Update our log with our error message */
                    UPDATE dbo.dba_indexDefragLog
                    SET dateTimeEnd = GETDATE()
                        , durationSeconds = -1
                        , errorMessage = ERROR_MESSAGE()
                    WHERE indexDefrag_id = @indexDefrag_id;

                    IF @debugMode = 1 
                        RAISERROR('  An error has occurred executing this command! Please review the dba_indexDefragLog table for details.'
                            , 0, 42) WITH NOWAIT;

                END CATCH

                /* Just a little breather for the server */
                WAITFOR DELAY @defragDelay;

                UPDATE dbo.dba_indexDefragStatus
                SET defragDate = GETDATE()
                    , printStatus = 1
                WHERE databaseID       = @databaseID
                  AND objectID         = @objectID
                  AND indexID          = @indexID
                  AND partitionNumber  = @partitionNumber;

            END
            ELSE
            /* Looks like we're not executing, just printing the commands */
            BEGIN
                IF @debugMode = 1 RAISERROR('  Printing SQL statements...', 0, 42) WITH NOWAIT;
                
                IF @printCommands = 1 OR @debugMode = 1 
                    PRINT ISNULL(@sqlCommand, 'error!');

                UPDATE dbo.dba_indexDefragStatus
                SET printStatus = 1
                WHERE databaseID       = @databaseID
                  AND objectID         = @objectID
                  AND indexID          = @indexID
                  AND partitionNumber  = @partitionNumber;
            END

        END

        /* Do we want to output our fragmentation results? */
        IF @printFragmentation = 1
        BEGIN

            IF @debugMode = 1 RAISERROR('  Displaying a summary of our action...', 0, 42) WITH NOWAIT;

            SELECT databaseID
                , databaseName
                , objectID
                , objectName
                , indexID
                , indexName
                , partitionNumber
                , fragmentation
                , page_count
                , range_scan_count
            FROM dbo.dba_indexDefragStatus
            WHERE defragDate >= @startdatetime
            ORDER BY defragDate;

        END;

    END TRY
    BEGIN CATCH

        SET @debugMessage = ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')';
        PRINT @debugMessage;

    END CATCH;

    /* When everything is said and done, make sure to get rid of our temp table */
    DROP TABLE #databaseList;
    DROP TABLE #processor;
    DROP TABLE #maxPartitionList;

    IF @debugMode = 1 RAISERROR('DONE!  Thank you for taking care of your indexes!  :)', 0, 42) WITH NOWAIT;

    SET NOCOUNT OFF;
    RETURN 0;
END
