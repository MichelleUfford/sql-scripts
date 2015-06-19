If ObjectProperty(Object_ID('dbo.dba_indexStats_sp'), N'IsProcedure') = 1
Begin
    Drop Procedure dbo.dba_indexStats_sp;
    Print 'Procedure dba_indexStats_sp dropped';
End;
Go

Set Quoted_Identifier On
Go
Set ANSI_Nulls On
Go

Create Procedure dbo.dba_indexStats_sp

        /* Declare Parameters */
          @databaseName         varchar(256)    = Null
        , @indexType            varchar(256)    = Null
        , @minRowCount          int             = Null
        , @maxRowCount          int             = Null
        , @minSeekScanLookup    int             = Null
        , @maxSeekScanLookup    int             = Null
As
/**********************************************************************************************************

    NAME:           dba_indexStats_sp

    SYNOPSIS:       Retrieves information regarding indexes; will return drop SQL
                    statement for non-clustered indexes.

    DEPENDENCIES:   The following dependencies are required to execute this script:
                    - SQL Server 2005 or newer

    NOTES:          @databaseName - optional, specify a specific database to interrogate;
                    by default, all user databases will be returned

                    @indexType - optional, valid options are: 
                                    Clustered
                                    NonClustered
                                    Unique Clustered
                                    Unique NonClustered
                                    Heap
    
                    @minRowCount - optional, specify a minimum number of rows an index
                                    must cover
    
                    @maxRowCount - optional, specify a maximum number of rows an index
                                    must cover
    
                    @minSeekScanLookup - optional, min sum aggregation of index scans, 
                                    seeks, and look-ups.  Useful for finding unused indexes
    
                    @minSeekScanLookup - optional, max sum aggregation of index scans,  
                                    seeks, and look-ups.  Useful for finding unused indexes

    AUTHOR:         Michelle Ufford, http://sqlfool.com
    
    CREATED:        2008-07-11
    
    VERSION:        1.0

    LICENSE:        Apache License v2
    
    USAGE:          EXEC dbo.dba_indexStats_sp
                      @databaseName         = 'your_db'
                    , @indexType            = 'NonClustered'
                    , @minSeekScanLookup    = 0
                    , @maxSeekScanLookup    = 1000
                    , @minRowCount          = 0
                    , @maxRowCount          = 10000000;

    ----------------------------------------------------------------------------
    DISCLAIMER: 
    This code and information are provided "AS IS" without warranty of any kind,
    either expressed or implied, including but not limited to the implied 
    warranties or merchantability and/or fitness for a particular purpose.
    ----------------------------------------------------------------------------

 ---------------------------------------------------------------------------------------------------------
 --  DATE       VERSION     AUTHOR                  DESCRIPTION                                        --
 ---------------------------------------------------------------------------------------------------------
     20150619   1.0         Michelle Ufford         Open Sourced on GitHub
**********************************************************************************************************/

Set NoCount On;
Set XACT_Abort On;

Begin

    /* Declare Variables */
        Create Table #indexStats 
        (
              databaseName          varchar(256)
            , objectName            varchar(256)
            , indexName             varchar(256)
            , indexType             varchar(256)
            , user_seeks            int
            , user_scans            int
            , user_lookups          int
            , user_updates          int
            , total_seekScanLookup  int
            , rowCounts             int
            , SQL_DropStatement     varchar(2000)
        );

    /* Check for existing transactions;
       If one exists, exit with error. */
    If @@TranCount > 0 
    Begin

        /* Log the fact that there were open transactions */
        Execute dbo.dba_logError_sp @errorType = 'app'
            , @app_errorProcedure = 'dba_indexStats_sp'
            , @app_errorMessage = 'Open transaction exists; dba_indexStats_sp proc will not execute.';
          Print 'Open transactions exist!';

    End
    Else
    Begin
        Begin Try

        Execute sp_MSForEachDB 'Use [?]

        Declare @dbid int
            , @dbName varchar(100);

        Select @dbid = DB_ID()
            , @dbName = DB_Name();

        With indexSizeCTE (object_id, index_id, rowCounts) As
        (
            Select [object_id]
                , index_id
                , Sum([rows]) As ''rowCounts''
            From sys.partitions
            Group By [object_id]
                , index_id
        ) 

        Insert Into #indexStats
        Select  
                  @dbName
                , Object_Name(ix.[object_id]) as objectName
                , ix.name As ''indexName''
                , Case 
                    When ix.is_unique = 1 
                        Then ''UNIQUE ''
                    Else ''''
                  End + ix.type_desc As ''indexType''
                , ddius.user_seeks
                , ddius.user_scans
                , ddius.user_lookups
                , ddius.user_updates
                , ddius.user_seeks + ddius.user_scans + ddius.user_lookups
                , isc.rowCounts
                , Case 
                    When ix.type = 2 And ix.is_unique = 0
                        Then ''Drop Index '' + ix.name + '' On '' + @dbName + ''.dbo.'' + Object_Name(ddius.[object_id]) + '';''
                    When ix.type = 2 And ix.is_unique = 1
                        Then ''Alter Table '' + @dbName + ''.dbo.'' + Object_Name(ddius.[object_ID]) + '' Drop Constraint '' + ix.name + '';''
                    Else '' ''
                  End As ''SQL_DropStatement''
        From sys.indexes As ix
            Left Outer Join sys.dm_db_index_usage_stats ddius
                On ix.object_id = ddius.object_id
                    And ix.index_id = ddius.index_id
            Left Outer Join indexSizeCTE As isc
                On ix.object_id = isc.object_id
                    And ix.index_id = isc.index_id
        Where ddius.database_id = @dbid
            And ObjectProperty(ix.[object_id], N''IsUserTable'') = 1
        Order By (ddius.user_seeks + ddius.user_scans + ddius.user_lookups) Asc;
        '

        Select databaseName
            , objectName
            , indexName
            , indexType
            , user_seeks
            , user_scans
            , user_lookups
            , total_seekScanLookup
            , user_updates
            , rowCounts
            , SQL_DropStatement
        From #indexStats
        Where databaseName = IsNull(@databaseName, databaseName)
          And indexType = IsNull(@indexType, indexType)
          And rowCounts Between IsNull(@minRowCount, rowCounts) And IsNull(@maxRowCount, rowCounts)
          And total_seekScanLookup Between IsNull(@minSeekScanLookup, total_seekScanLookup) And IsNull(@maxSeekScanLookup, total_seekScanLookup)
          And databaseName Not In ('master', 'msdb', 'tempdb', 'model')
        Order By total_seekScanLookup;

        End Try
        Begin Catch

            /* Return an error message and log it */
              Execute dbo.dba_logError_sp;
              Print 'An error has occurred!';

        End Catch;
    End;

    /* Clean up! */
    Drop Table #indexStats;

    Set NoCount Off;
    Return 0;
End
Go

Set Quoted_Identifier Off;
Go
Set ANSI_Nulls On;
Go

If ObjectProperty(Object_ID('dbo.dba_indexStats_sp'), N'IsProcedure') = 1 
    RaisError('Procedure dba_indexStats_sp was successfully created.', 10, 1);
Else
    RaisError('Procedure dba_indexStats_sp FAILED to create!', 16, 1);
Go