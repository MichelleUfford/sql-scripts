Use DBAHoldings;
Go

If Object_ID('dbo.dba_replicationMonitor') Is Null
Begin
    Create Table dbo.dba_replicationMonitor
    ( 
          monitor_id            int Identity(1,1)   Not Null
        , monitorDate           smalldatetime       Not Null 
        , publicationName       sysname             Not Null
        , publicationDB         sysname             Not Null
        , iteration             int                 Null
        , tracer_id             int                 Null
        , distributor_latency   int                 Null
        , subscriber            varchar(1000)       Null
        , subscriber_db         varchar(1000)       Null
        , subscriber_latency    int                 Null
        , overall_latency       int                 Null 
    );
End;

If ObjectProperty(Object_ID('dbo.dba_replicationLatencyMonitor_sp'), N'IsProcedure') = 1
Begin
    Drop Procedure dbo.dba_replicationLatencyMonitor_sp;
    Print 'Procedure dba_replicationLatencyMonitor_sp dropped';
End;
Go

Set Quoted_Identifier On
Go
Set ANSI_Nulls On
Go

Create Procedure dbo.dba_replicationLatencyMonitor_sp

        /* Declare Parameters */
          @publicationToTest    sysname        = N'YourPublication01'
        , @publicationDB        sysname        = N'YourPublicationDB'
        , @replicationDelay     varchar(10)    = N'00:00:30'
        , @iterations           int            = 5
        , @iterationDelay       varchar(10)    = N'00:00:30'
        , @displayResults       bit            = 0
        , @deleteTokens         bit            = 1
As
/**********************************************************************************************************

    NAME:           dba_replicationLatencyMonitor_sp

    SYNOPSIS:       Retrieves the amount of replication latency in seconds

    DEPENDENCIES:   The following dependencies are required to execute this script:
                    - SQL Server 2005 or newer
                    
    NOTES:          Default settings will run 1 test every minute for 5 minutes.

                      @publicationToTest = defaults to the specified publication
                      
                      @publicationDB = the database that is the source for the publication.
      				        The tracer procs are found in the publishing DB.
      
                      @replicationDelay = how long to wait for the token to replicate;
                          probably should not set to anything less than 10 (in seconds)
      
                      @iterations = how many tokens you want to test
      
                      @iterationDelay = how long to wait between sending test tokens
                          (in seconds)
      
                      @displayResults = print results to screen when complete
      
                      @deleteTokens = whether you want to retain tokens when done

    AUTHOR:         Michelle Ufford, http://sqlfool.com
    
    CREATED:        2008-11-23
    
    VERSION:        1.0

    LICENSE:        Apache License v2

    USAGE:          EXEC dbo.dba_replicationLatencyMonitor_sp
                      @publicationToTest    = N'myTestPublication'
                    , @publicationDB        = N'sandbox_publisher'
                    , @replicationDelay     = N'00:00:05'
                    , @iterations           = 1
                    , @iterationDelay       = N'00:00:05'
                    , @displayResults       = 1
                    , @deleteTokens         = 1;

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
          , @currentDateTime    smalldatetime
          , @sqlStatement       nvarchar(200)
          , @parmDefinition		nvarchar(500);

    Declare @tokenResults Table
    ( 
          iteration             int             Null
        , tracer_id             int             Null
        , distributor_latency   int             Null
        , subscriber            varchar(1000)   Null
        , subscriber_db         varchar(1000)   Null
        , subscriber_latency    int             Null
        , overall_latency       int             Null 
    );

    /* Initialize our variables */
    Select @currentIteration = 0
         , @currentDateTime  = GetDate();

    While @currentIteration < @iterations
    Begin

		/* Prepare the stored procedure execution string */
		Set @sqlStatement = N'Execute ' + @publicationDB + N'.sys.sp_postTracerToken ' + 
							N'@publication = @VARpublicationToTest , ' +
							N'@tracer_token_id = @VARtokenID OutPut;'
	
		/* Define the parameters used by the sp_ExecuteSQL later */
		Set @parmDefinition = N'@VARpublicationToTest sysname, ' +
			N'@VARtokenID bigint OutPut';

        /* Insert a new tracer token in the publication database */
        Execute sp_executesql 
              @sqlStatement
            , @parmDefinition
            , @VARpublicationToTest = @publicationToTest
            , @VARtokenID = @TokenID OutPut;

        /* Give a few seconds to allow the record to reach the subscriber */
        WaitFor Delay @replicationDelay;
        
        /* Prepare our statement to retrieve tracer token data */
        Select @sqlStatement = 'Execute ' + @publicationDB + '.sys.sp_helpTracerTokenHistory ' +
                    N'@publication = @VARpublicationToTest , ' +
                    N'@tracer_id = @VARtokenID'
            , @parmDefinition = N'@VARpublicationToTest sysname, ' +
                    N'@VARtokenID bigint';

        /* Store our results for retrieval later */
        Insert Into @tokenResults
        (
            distributor_latency
          , subscriber
          , subscriber_db
          , subscriber_latency
          , overall_latency
        )
        Execute sp_executesql 
              @sqlStatement
            , @parmDefinition
            , @VARpublicationToTest = @publicationToTest
            , @VARtokenID = @TokenID;

        /* Assign the iteration and token id to the results for easier investigation */
        Update @tokenResults
        Set iteration = @currentIteration + 1
          , tracer_id = @tokenID
        Where iteration Is Null;

        /* Wait for the specified time period before creating another token */
        WaitFor Delay @iterationDelay;

        /* Avoid endless looping... :) */
        Set @currentIteration = @currentIteration + 1;

    End;

    /* Display our results */
    If @displayResults = 1
    Begin
        Select 
              iteration
            , tracer_id
            , IsNull(distributor_latency, 0) As 'distributor_latency'
            , subscriber
            , subscriber_db
            , IsNull(subscriber_latency, 0) As 'subscriber_latency'
            , IsNull(overall_latency, 
                IsNull(distributor_latency, 0) + IsNull(subscriber_latency, 0))
                As 'overall_latency'
        From @tokenResults;
    End;

    /* Store our results */
    Insert Into dbo.dba_replicationMonitor
    (
          monitorDate
        , publicationName
        , publicationDB
        , iteration
        , tracer_id
        , distributor_latency
        , subscriber
        , subscriber_db
        , subscriber_latency
        , overall_latency
    )
    Select 
          @currentDateTime
        , @publicationToTest
        , @publicationDB
        , iteration
        , tracer_id
        , IsNull(distributor_latency, 0)
        , subscriber
        , subscriber_db
        , IsNull(subscriber_latency, 0)
        , IsNull(overall_latency, 
            IsNull(distributor_latency, 0) + IsNull(subscriber_latency, 0))
    From @tokenResults;

    /* Delete the tracer tokens if requested */
    If @deleteTokens = 1
    Begin
    
        Select @sqlStatement = 'Execute ' + @publicationDB + '.sys.sp_deleteTracerTokenHistory ' +
                    N'@publication = @VARpublicationToTest , ' +
                    N'@cutoff_date = @VARcurrentDateTime'
            , @parmDefinition = N'@VARpublicationToTest sysname, ' +
                    N'@VARcurrentDateTime datetime';
	        
        Execute sp_executesql 
              @sqlStatement
            , @parmDefinition
            , @VARpublicationToTest = @publicationToTest
            , @VARcurrentDateTime = @currentDateTime;
    
    End;

    Set NoCount Off;
    Return 0;
End
Go

Set Quoted_Identifier Off;
Go
Set ANSI_Nulls On;
Go

If ObjectProperty(Object_ID('dbo.dba_replicationLatencyMonitor_sp'), N'IsProcedure') = 1 
    RaisError('Procedure dba_replicationLatencyMonitor_sp was successfully created.', 10, 1);
Else
    RaisError('Procedure dba_replicationLatencyMonitor_sp FAILED to create!', 16, 1);
Go
