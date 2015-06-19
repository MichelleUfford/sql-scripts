Use dbaTools;
Go

/* Create a stored procedure skeleton */
If ObjectProperty(Object_ID('dbo.dba_missingIndexStoredProc_sp'), N'IsProcedure') Is Null
Begin
    Execute ('Create Procedure dbo.dba_missingIndexStoredProc_sp As Print ''Hello World!''')
    RaisError('Procedure dba_missingIndexStoredProc_sp created.', 10, 1);
End;
Go

/* Drop our table if it already exists */
If Exists(Select Object_ID From sys.tables Where [name] = N'dba_missingIndexStoredProc')
Begin
    Drop Table dbo.dba_missingIndexStoredProc
    Print 'dba_missingIndexStoredProc table dropped!';
End

/* Create our table */
Create Table dbo.dba_missingIndexStoredProc
(
      missingIndexSP_id     int Identity(1,1)   Not Null
    , databaseName          varchar(128)        Not Null
    , databaseID            int                 Not Null
    , objectName            varchar(128)        Not Null
    , objectID              int                 Not Null
    , query_plan            xml                 Not Null
    , executionDate         smalldatetime       Not Null
    , statementExecutions   int                 Not Null
    
    Constraint PK_missingIndexStoredProc
        Primary Key Clustered(missingIndexSP_id)
);

Print 'dba_missingIndexStoredProc Table Created';

/* Configure our settings */
Set ANSI_Nulls On;
Set Quoted_Identifier On;
Go

Alter Procedure dbo.dba_missingIndexStoredProc_sp

        /* Declare Parameters */
            @lastExecuted_inDays    int = 7
          , @minExecutionCount      int = 1
          , @logResults             bit = 1
          , @displayResults         bit = 0

As
/**********************************************************************************************************

    NAME:           dba_missingIndexStoredProc_sp

    SYNOPSIS:       Retrieves stored procedures with missing indexes in their cached query plans.
                
                    @lastExecuted_inDays = number of days old the cached query plan
                                       can be to still appear in the results;
                                       the HIGHER the number, the longer the
                                       execution time.

                    @minExecutionCount = minimum number of executions the cached
                                     query plan can have to still appear 
                                     in the results; the LOWER the number,
                                     the longer the execution time.

                    @logResults = store results in dba_missingIndexStoredProc
                
                    @displayResults = return results to the caller

    DEPENDENCIES:   The following dependencies are required to execute this script:
                    - SQL Server 2005 or newer

    NOTES:          This is not 100% guaranteed to catch all missing indexes in
                    a stored procedure.  It will only catch it if the stored proc's
                    query plan is still in cache.  Run regularly to help minimize
                    the chance of missing a proc.

    AUTHOR:         Michelle Ufford, http://sqlfool.com
    
    CREATED:        2009-09-03
    
    VERSION:        1.0

    LICENSE:        Apache License v2
    
    USAGE:          Exec dbo.dba_missingIndexStoredProc_sp
                      @lastExecuted_inDays  = 30
                    , @minExecutionCount    = 5
                    , @logResults           = 1
                    , @displayResults       = 1;

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
Set Ansi_Padding On;
Set Ansi_Warnings On;
Set ArithAbort On;
Set Concat_Null_Yields_Null On;
Set Numeric_RoundAbort Off;

Begin

    /* Declare Variables */
    Declare @currentDateTime smalldatetime;

    Set @currentDateTime = GetDate();

    Declare @plan_handles Table
    (
          plan_handle           varbinary(64)   Not Null
        , statementExecutions   int             Not Null
    );

    Create Table #missingIndexes
    (
          databaseID            int             Not Null
        , objectID              int             Not Null
        , query_plan            xml             Not Null
        , statementExecutions   int             Not Null
    );
    
    Create Clustered Index CIX_temp_missingIndexes
        On #missingIndexes(databaseID, objectID);
       
    Begin Try

        /* Perform some data validation */
        If @logResults = 0 And @displayResults = 0
        Begin

            /* Log the fact that there were open transactions */
            Execute dbo.dba_logError_sp
                  @errorType            = 'app'
                , @app_errorProcedure   = 'dba_missingIndexStoredProc_sp'
                , @app_errorMessage     = '@logResults = 0 and @displayResults = 0; no action taken, exiting stored proc.'
                , @forceExit            = 1
                , @returnError          = 1;  

        End;

        Begin Transaction;

        /* Retrieve distinct plan handles to minimize dm_exec_query_plan lookups */
        Insert Into @plan_handles
        Select plan_handle, Sum(execution_count) As 'executions'
        From sys.dm_exec_query_stats
        Where last_execution_time > DateAdd(day, -@lastExecuted_inDays, @currentDateTime)
        Group By plan_handle
        Having Sum(execution_count) > @minExecutionCount;

        With xmlNameSpaces (
            Default 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'
        )

        /* Retrieve our query plan's XML if there's a missing index */
        Insert Into #missingIndexes
        Select deqp.[dbid]
            , deqp.objectid
            , deqp.query_plan 
            , ph.statementExecutions
        From @plan_handles As ph
        Cross Apply sys.dm_exec_query_plan(ph.plan_handle) As deqp 
        Where deqp.query_plan.exist('//MissingIndex/@Database') = 1
            And deqp.objectid Is Not Null;

        /* Do we want to store the results of our process? */
        If @logResults = 1
        Begin
            Insert Into dbo.dba_missingIndexStoredProc
            Execute sp_msForEachDB 'Use ?; 
                                    Select ''?''
                                        , mi.databaseID
                                        , Object_Name(o.object_id)
                                        , o.object_id
                                        , mi.query_plan
                                        , GetDate()
                                        , mi.statementExecutions
                                    From sys.objects As o 
                                    Join #missingIndexes As mi 
                                        On o.object_id = mi.objectID 
                                    Where databaseID = DB_ID();';

        End
        /* We're not logging it, so let's display it */
        Else
        Begin
            Execute sp_msForEachDB 'Use ?; 
                                    Select ''?''
                                        , mi.databaseID
                                        , Object_Name(o.object_id)
                                        , o.object_id
                                        , mi.query_plan
                                        , GetDate()
                                        , mi.statementExecutions
                                    From sys.objects As o 
                                    Join #missingIndexes As mi 
                                        On o.object_id = mi.objectID 
                                    Where databaseID = DB_ID();';
        End;

        /* See above; this part will only work if we've 
           logged our data. */
        If @displayResults = 1 And @logResults = 1
        Begin
            Select *
            From dbo.dba_missingIndexStoredProc
            Where executionDate >= @currentDateTime;
        End;

        /* If you have an open transaction, commit it */
        If @@TranCount > 0
            Commit Transaction;

    End Try
    Begin Catch

        /* Whoops, there was an error... rollback! */
        If @@TranCount > 0
            Rollback Transaction;

        /* Return an error message and log it */
        Execute dbo.dba_logError_sp;

    End Catch;

    /* Clean-Up! */
    Drop Table #missingIndexes;

    Set NoCount Off;
    Return 0;
End
Go

Set Quoted_Identifier Off;
Go