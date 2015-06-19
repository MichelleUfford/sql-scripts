If ObjectProperty(Object_ID('dbo.dba_replicationLatencyGet_sp'), N'IsProcedure') = 1
Begin
    Drop Procedure dbo.dba_replicationLatencyGet_sp;
    Print 'Procedure dba_replicationLatencyGet_sp dropped';
End;
Go

Set Quoted_Identifier On
Go
Set ANSI_Nulls On
Go

Create Procedure dbo.dba_replicationLatencyGet_sp

        /* Declare Parameters */
          @publicationToTest sysname        = N'goDaddyWebsiteTracking01'
        , @replicationDelay  varchar(10)    = N'00:00:30'
        , @iterations        int            = 5
        , @iterationDelay    varchar(10)    = N'00:00:30'
        , @deleteTokens      bit            = 1
        , @deleteTempTable   bit            = 1
As
/**********************************************************************************************************

    NAME:           dba_replicationLatencyGet_sp

    SYNOPSIS:       Retrieves the amount of replication latency in seconds

    DEPENDENCIES:   The following dependencies are required to execute this script:
                    - SQL Server 2005 or newer
                    
    NOTES:          Default settings will run 1 test every minute for 5 minutes.

                    @publicationToTest = defaults to goDaddyWebsiteTracking publication
    
                    @replicationDelay = how long to wait for the token to replicate;
                        probably should not set to anything less than 10 (in seconds)
    
                    @iterations = how many tokens you want to test
    
                    @iterationDelay = how long to wait between sending test tokens
                        (in seconds)
    
                    @deleteTokens = whether you want to retain tokens when done
    
                    @deleteTempTable = whether or not to retain the temporary table
                        when done.  Data stored to ##tokenResults; set @deleteTempTable 
                        flag to 0 if you do not want to delete when done.

    AUTHOR:         Michelle Ufford, http://sqlfool.com
    
    CREATED:        2008-05-22
    
    VERSION:        1.0

    LICENSE:        Apache License v2

    USAGE:          EXEC dbo.dba_replicationLatencyGet_sp
                      @publicationToTest    = N'your_publication'
                    , @replicationDelay     = N'00:00:05'
                    , @iterations           = 1
                    , @iterationDelay       = N'00:00:05'
                    , @deleteTokens         = 1
                    , @deleteTempTable      = 1;

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
    Declare @currentIteration   int
          , @tokenID            bigint
          , @currentDateTime    smalldatetime;

    If Object_ID('tempdb.dbo.##tokenResults') Is Null
    Begin
        Create Table ##tokenResults
                        ( iteration           int             Null
                        , tracer_id           int             Null
                        , distributor_latency int             Null
                        , subscriber          varchar(1000)   Null
                        , subscriber_db       varchar(1000)   Null
                        , subscriber_latency  int             Null
                        , overall_latency     int             Null );
    End;

    /* Initialize our variables */
    Select @currentIteration = 0
         , @currentDateTime  = GetDate();

    While @currentIteration < @iterations
    Begin

        /* Insert a new tracer token in the publication database */
        Execute sys.sp_postTracerToken 
          @publication = @publicationToTest,
          @tracer_token_id = @tokenID OutPut;

        /* Give a few seconds to allow the record to reach the subscriber */
        WaitFor Delay @replicationDelay;

        /* Store our results in a temp table for retrieval later */
        Insert Into ##tokenResults
        (
            distributor_latency
          , subscriber
          , subscriber_db
          , subscriber_latency
          , overall_latency
        )
        Execute sys.sp_helpTracerTokenHistory @publicationToTest, @tokenID;

        /* Assign the iteration and token id to the results for easier investigation */
        Update ##tokenResults
        Set iteration = @currentIteration + 1
          , tracer_id = @tokenID
        Where iteration Is Null;

        /* Wait for the specified time period before creating another token */
        WaitFor Delay @iterationDelay;

        /* Avoid endless looping... :) */
        Set @currentIteration = @currentIteration + 1;

    End;

    Select * From ##tokenResults;

    If @deleteTempTable = 1
    Begin
        Drop Table ##tokenResults;
    End;

    If @deleteTokens = 1
    Begin
       Execute sp_deleteTracerTokenHistory @publication = @publicationToTest, @cutoff_date = @currentDateTime;
    End;

    Set NoCount Off;
    Return 0;
End
Go

Set Quoted_Identifier Off;
Go
Set ANSI_Nulls On;
Go

If ObjectProperty(Object_ID('dbo.dba_replicationLatencyGet_sp'), N'IsProcedure') = 1 
    RaisError('Procedure dba_replicationLatencyGet_sp was successfully created.', 10, 1);
Else
    RaisError('Procedure dba_replicationLatencyGet_sp FAILED to create!', 16, 1);
Go
