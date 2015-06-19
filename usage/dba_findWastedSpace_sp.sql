If ObjectProperty(Object_ID('dbo.dba_findWastedSpace_sp'), N'IsProcedure') Is Null
Begin
    Execute ('Create Procedure dbo.dba_findWastedSpace_sp As Print ''Hello World!''')
    RaisError('Procedure dba_findWastedSpace_sp created.', 10, 1);
End;
Go

Set ANSI_Nulls On;
Set Quoted_Identifier On;
Go

Alter Procedure dbo.dba_findWastedSpace_sp

    /* Declare Parameters */
      @databaseName     sysname     = 'AdventureWorks'
    , @tableName        sysname     = 'Sales.SalesOrderDetail'
    , @percentGrowth    tinyint     = 10    /* allow for up to 10% growth by default */
    , @displayUnit      char(2)     = 'GB'  /* KB, MB, GB, or TB */
    , @debug            bit         = 1

As
/**********************************************************************************************************

    NAME:           dba_findWastedSpace_sp

    SYNOPSIS:       Finds wasted space on a database and/or table

    DEPENDENCIES:   The following dependencies are required to execute this script:
                    - SQL Server 2005 or newer

    AUTHOR:         Michelle Ufford, http://sqlfool.com
    
    CREATED:        2011-03-14
    
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

    /* Make sure our environment is clean and ready to go */
    If Exists(Select object_id From tempdb.sys.tables Where name = '##values')
        Drop Table ##values;

    If Exists(Select object_id From tempdb.sys.tables Where name = '##definition')
        Drop Table ##definition;

    If Exists(Select object_id From tempdb.sys.tables Where name = '##spaceRequired')
        Drop Table ##spaceRequired;

    If Exists(Select object_id From tempdb.sys.tables Where name = '##results')
        Drop Table ##results;

    /* Declare Variables */
    Declare @sqlStatement_getColumnList     nvarchar(max)
        , @sqlStatement_values              nvarchar(max)
        , @sqlStatement_columns             nvarchar(max)
        , @sqlStatement_tableDefinition1    nvarchar(max)
        , @sqlStatement_tableDefinition2    nvarchar(max)
        , @sqlStatement_tableDefinition3    nvarchar(max)
        , @sqlStatement_spaceRequired       nvarchar(max)
        , @sqlStatement_results             nvarchar(max)
        , @sqlStatement_displayResults      nvarchar(max)
        , @sqlStatement_total               nvarchar(max)
        , @currentRecord                    int
        , @growthPercentage                 float;

    Declare @columnList Table
    (
          id            int identity(1,1)
        , table_id      int
        , columnName    varchar(128)
        , user_type_id  tinyint
        , max_length    smallint
        , columnStatus  tinyint
    );

    /* Initialize variables
            I'm doing it this way to support 2005 environments, too */
    Select @sqlStatement_tableDefinition1   = ''
        , @sqlStatement_tableDefinition2    = ''
        , @sqlStatement_tableDefinition3    = ''
        , @sqlStatement_spaceRequired       = 'Select '
        , @sqlStatement_results             = 'Select '
        , @sqlStatement_displayResults      = ''
        , @sqlStatement_total               = 'Select ''Total'', Null, '
        , @sqlStatement_values              = 'Select '
        , @sqlStatement_columns             = 'Select '
        , @growthPercentage                 = 1+(@percentGrowth/100.0);

    Set @sqlStatement_getColumnList = '
    Select c.object_id As [table_id]
        , c.name
        , t.user_type_id
        , c.max_length
        , 0 /* not yet columnStatus */
    From ' + @databaseName + '.sys.columns As c
    Join ' + @databaseName + '.sys.types As t 
        On c.user_type_id = t.user_type_id
    Where c.object_id = IsNull(Object_Id(''' + @databaseName + '.' + @tableName + '''), c.object_id)
        And t.user_type_id In (48, 52, 56, 127, 167, 175, 231, 239);'

    If @Debug = 1
    Begin
        Select @sqlStatement_getColumnList;
    End;

    Insert Into @columnList 
    Execute sp_executeSQL @sqlStatement_getColumnList;

    If @Debug = 1
    Begin
        Select * From @columnList;
    End;

    /* Begin our loop.  We're going to run through this for every column.  */
    While Exists(Select * From @columnList Where columnStatus = 0)
    Begin

        /* Grab a column that hasn't been processed yet */
        Select Top 1 @currentRecord = id 
        From @columnList
        Where columnStatus = 0
        Order By id;

        /* First, let's build the statement we're going to use to get our min/max values */
        Select @sqlStatement_values = @sqlStatement_values + Case When user_type_id In (48, 52, 56, 127) 
                Then 'Max(' + columnName + ') As [' + columnName + '], ' 
                    + 'Min(' + columnName + ') As [min' + columnName + '], '
                Else 'Max(Len(' + columnName + ')) As [' + columnName + '], ' 
                    + 'Avg(Len(' + columnName + ')) As [avg' + columnName + '], '
                End 
        From @columnList
        Where id = @currentRecord;

        /* Next, let's build the statement that's going to show us how much space the column is currently consuming */
        Select @sqlStatement_columns = @sqlStatement_columns 
            + Case  When user_type_id = 48  Then '1' -- tinyint
                    When user_type_id = 52  Then '2' -- smallint
                    When user_type_id = 56  Then '4' -- int
                    When user_type_id = 127 Then '8' -- bigint
                    When user_type_id In (167, 175) Then Cast(max_length As varchar(10))-- varchar or char
                    Else Cast(max_length * 2 As varchar(10)) -- nvarchar or nchar
                    --Else '0'
                End + ' As [' + columnName + '], ' 
        From @columnList
        Where id = @currentRecord;

        /* This section is used to build a table definition */
        Select @sqlStatement_tableDefinition1 = @sqlStatement_tableDefinition1 + '[' + columnName + '] ' 
            + Case  
                When user_type_id = 48  Then 'tinyint'
                When user_type_id = 52  Then 'smallint'
                When user_type_id = 56  Then 'int'
                When user_type_id = 127 Then 'bigint'
                Else 'smallint'
              End + ', ' 
            + Case When user_type_id In (48, 52, 56, 127) Then '[min' Else '[avg' End + columnName + '] '
            + Case  
                When user_type_id = 48  Then 'tinyint'
                When user_type_id = 52  Then 'smallint'
                When user_type_id = 56  Then 'int'
                When user_type_id = 127 Then 'bigint'
                Else 'smallint'
              End + ', ' 
        From @columnList
        Where id = @currentRecord;

        /* More dynamic table definition code */
        Select @sqlStatement_tableDefinition2 = @sqlStatement_tableDefinition2 + '[' + columnName + '] ' 
            + Case  
                When user_type_id = 48  Then 'tinyint'
                When user_type_id = 52  Then 'smallint'
                When user_type_id = 56  Then 'int'
                When user_type_id = 127 Then 'bigint'
                Else 'smallint'
              End + ', ' 
        From @columnList
        Where id = @currentRecord;

        /* And yet more dynamic table definition code */
        Select @sqlStatement_tableDefinition3 = @sqlStatement_tableDefinition3 + columnName + ' smallint, '
                                                    + columnName + '_bytes bigint, '
        From @columnList
        Where id = @currentRecord;

        /* This is where we see how much space we actually need, based on our min/max values.
           This is where we consider the % of growth that we expect to see in a reasonable period of time. */
        Select @sqlStatement_spaceRequired = @sqlStatement_spaceRequired + 
            Case When user_type_id In (48, 52, 56, 127)
                Then 'Case When ([' + columnName + '] * ' + Cast(@growthPercentage As varchar(5)) + ') <= 255 
                                And [min' + columnName + '] >= 0 
                                    Then 1
                           When ([' + columnName + '] * ' + Cast(@growthPercentage As varchar(5)) + ') <= 32768 
                                And [min' + columnName + '] >= -32768 
                                    Then 2
                           When ([' + columnName + '] * ' + Cast(@growthPercentage As varchar(5)) + ') <= 2147483647 
                                And [min' + columnName + '] >= -2147483647 
                                    Then 4
                           Else 8 End '
                Else columnName
            End + ' As [' + columnName + '], '
        From @columnList
        Where id = @currentRecord;
        
        /* This is where the analysis occurs to tell us how much space we're potentially wasting */
        Select @sqlStatement_results = @sqlStatement_results + 
            'd.[' + columnName + '] - sr.[' + columnName + '] As [' + columnName + '], ' +
            '(d.[' + columnName + '] - sr.[' + columnName + ']) * rowCnt As [bytes], '
        From @columnList
        Where id = @currentRecord;

        /* This is where we get our pretty results table from */
        Select @sqlStatement_displayResults = @sqlStatement_displayResults + 'Select ''' + columnName + ''' As [columnName] '
                                                + ', ' + columnName + ' As [byteReduction] '
                                                -- + ', ' + columnName + '_bytes As [estimatedSpaceSavings] '
                                                + ', ' + columnName + '_bytes / 1024.0 / 1024.0 As [estimatedSpaceSavings] '
                                                + ' From ##results'
                                                + ' Union All '
        From @columnList
        Where id = @currentRecord;

        /* And lastly, this is where we get our total from */
        Select @sqlStatement_total = @sqlStatement_total + '([' + columnName + '_bytes] / 1024.0 / 1024.0) + ' 
        From @columnList
        Where id = @currentRecord;


        /* Mark the column as processed so we can move on to the next one */
        Update @columnList 
        Set columnStatus = 1
        Where id = @currentRecord;

    End;

    Select @sqlStatement_values = @sqlStatement_values + ' Count(*) As [rowCnt], 1 As [id] From ' + @databaseName + '.' + @tableName + ' Option (MaxDop 1);'
        , @sqlStatement_columns = @sqlStatement_columns + ' ' + Cast(@currentRecord As varchar(4)) + ' As [columnCnt], 1 As [id];';

    Set @sqlStatement_tableDefinition1 = 'Create Table ##values(' 
                                        + @sqlStatement_tableDefinition1 
                                        + ' rowCnt bigint, id tinyint)';

    Set @sqlStatement_tableDefinition2 = 'Create Table ##definition(' 
                                        + @sqlStatement_tableDefinition2
                                        + ' columnCnt bigint, id tinyint)';

    Set @sqlStatement_tableDefinition3 = 'Create Table ##results(' 
                                        + @sqlStatement_tableDefinition3
                                        + ' id tinyint)';

    Set @sqlStatement_spaceRequired = @sqlStatement_spaceRequired + '1 As [id] Into ##spaceRequired From ##values;'

    Set @sqlStatement_results = @sqlStatement_results + '1 As [id] From ##definition As d Join ##spaceRequired As sr On d.id = sr.id Join ##values As v On d.id = v.id;'

    Set @sqlStatement_displayResults = @sqlStatement_displayResults + @sqlStatement_total + '0 From ##results';

    /* Print our dynamic SQL statements in case we need to troubleshoot */
    If @debug = 1
    Begin
        Select @sqlStatement_values As '@sqlStatement_values'
            , @sqlStatement_columns As '@sqlStatement_columns'
            , @sqlStatement_tableDefinition1 As '@sqlStatement_tableDefinition1'
            , @sqlStatement_tableDefinition2 As '@sqlStatement_tableDefinition2'
            , @sqlStatement_spaceRequired As '@sqlStatement_spaceRequired'
            , @sqlStatement_results As '@sqlStatement_results'
            , @sqlStatement_displayResults As '@sqlStatement_displayResults'
            , @sqlStatement_total As '@sqlStatement_total';
    End;

    Select @sqlStatement_tableDefinition1 As 'Table Definition 1';
    Execute sp_executeSQL @sqlStatement_tableDefinition1;

    Select @sqlStatement_tableDefinition2 As 'Table Definition 2';
    Execute sp_executeSQL @sqlStatement_tableDefinition2;

    Select @sqlStatement_tableDefinition3 As 'Table Definition 3';
    Execute sp_executeSQL @sqlStatement_tableDefinition3;

    Select @sqlStatement_values As 'Insert 1';
    Insert Into ##values 
    Execute sp_executeSQL @sqlStatement_values;

    Select @sqlStatement_columns As 'Insert 2';
    Insert Into ##definition 
    Execute sp_executeSQL @sqlStatement_columns;

    Select @sqlStatement_spaceRequired As 'Execute space required';
    Execute sp_executeSQL @sqlStatement_spaceRequired;

    Select @sqlStatement_results As 'Execute results';
    Insert Into ##results
    Execute sp_executeSQL @sqlStatement_results;

    /* Output our table values for troubleshooting purposes */
    If @debug = 1
    Begin
        Select 'definition' As 'tableType', * From ##definition y 
        Select 'values' As 'tableType', * from ##values x 
        Select 'spaceRequired' As 'tableType', * From ##spaceRequired;
        Select 'results' As 'tableType', * From ##results;
    End;

    Select @sqlStatement_displayResults As 'Final results';
    Execute sp_executeSQL @sqlStatement_displayResults;

    /* Clean up our mess */
    --Drop Table ##values;
    --Drop Table ##definition;
    --Drop Table ##spaceRequired;
    --Drop Table ##results;

    Set NoCount Off;
    Return 0;
End
Go

Set Quoted_Identifier Off;
Go