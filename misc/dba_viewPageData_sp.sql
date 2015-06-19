If ObjectProperty(Object_ID('dbo.dba_viewPageData_sp'), N'IsProcedure') Is Null
Begin
    Execute ('Create Procedure dbo.dba_viewPageData_sp As Print ''Hello World!''')
    RaisError('Procedure dba_viewPageData_sp created.', 10, 1);
End;
Go

Set ANSI_Nulls On;
Set Quoted_Identifier On;
Go

Alter Procedure dbo.dba_viewPageData_sp

        /* Declare Parameters */
          @databaseName varchar(128)
        , @tableName    varchar(128)    = Null -- database.schema.tableName
        , @indexName    varchar(128)    = Null
        , @fileNumber   int             = Null
        , @pageNumber   int             = Null
        , @printOption  int             = 3    -- 0, 1, 2, or 3
        , @pageType     char(4)         = 'Leaf' -- Leaf, Root, or IAM
        
As
/**********************************************************************************************************

    NAME:           dba_viewPageData_sp

    SYNOPSIS:       Retrieves page data for the specified table/page.

    DEPENDENCIES:   The following dependencies are required to execute this script:
                    - SQL Server 2005 or newer
                    
    NOTES:          Can pass either the table name or the pageID, but must pass one, or
                    you'll end up with no results. 
                    If the table name is passed, it will return the first page.
    
                    @tableName must be '<databaseName>.<schemaName>.<tableName>' in order to
                        function correctly.  When called within the same database, the database
                        prefix may be omitted.  
            
                    @printOption can be one of following values:
                        0 - print just the page header
                        1 - page header plus per-row hex dumps and a dump of the page slot array
                        2 - page header plus whole page hex dump
                        3 - page header plus detailed per-row interpretation
                        
                    Page Options borrowed from: 
                    https://blogs.msdn.com/sqlserverstorageengine/archive/2006/06/10/625659.aspx
            
                    @pageType must be one of the following values:
                        Leaf - returns the first page of the leaf level of your index or heap
                        Root - returns the root page of your index
                        IAM - returns the index allocation map chain for your index or heap
            
                    Conversions borrowed from:
                    http://sqlskills.com/blogs/paul/post/Inside-The-Storage-Engine-
                    sp_AllocationMetadata-putting-undocumented-system-catalog-views-to-work.aspx

    AUTHOR:         Michelle Ufford, http://sqlfool.com
    
    CREATED:        2009-05-06
    
    VERSION:        1.0

    LICENSE:        Apache License v2
    
    USAGE:          EXEC dbo.dba_viewPageData_sp
                      @databaseName = 'AdventureWorks'
                    , @tableName    = 'AdventureWorks.Sales.SalesOrderDetail'
                    , @indexName    = 'IX_SalesOrderDetail_ProductID'
                    --, @fileNumber   = 1
                    --, @pageNumber   = 38208
                    , @printOption  = 3
                    , @pageType     = 'Root';

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

    Declare @fileID         int
        , @pageID           int
        , @sqlStatement     nvarchar(1200)
        , @sqlParameters    nvarchar(255)
        , @errorMessage     varchar(100);

    Begin Try

        If @fileNumber Is Null And @pageNumber Is Null And @tableName Is Null
        Begin
            Set @errorMessage = 'You must provide either a file/page number, or a table name!';
            RaisError(@errorMessage, 16, 1);
        End;
            
        If @pageType Not In ('Leaf', 'Root', 'IAM')
        Begin
            Set @errorMessage = 'You have entered an invalid page type; valid options are "Leaf", "Root", or "IAM"';
            RaisError(@errorMessage, 16, 1);
        End;

        If @fileNumber Is Null Or @pageNumber Is Null
        Begin
        
            Set @sqlStatement = 
            Case When @pageType = 'Leaf' Then
                'Select Top 1 @p_fileID = Convert (varchar(6), Convert (int, 
                    SubString (au.first_page, 6, 1) +
                    SubString (au.first_page, 5, 1)))
                , @p_pageID = Convert (varchar(20), Convert (int, 
                     SubString (au.first_page, 4, 1) +
                     SubString (au.first_page, 3, 1) +
                     SubString (au.first_page, 2, 1) +
                     SubString (au.first_page, 1, 1)))'
            When @pageType = 'Root' Then
                'Select Top 1 @p_fileID = Convert (varchar(6), Convert (int, 
                    SubString (au.root_page, 6, 1) +
                    SubString (au.root_page, 5, 1)))
                , @p_pageID = Convert (varchar(20), Convert (int, 
                     SubString (au.root_page, 4, 1) +
                     SubString (au.root_page, 3, 1) +
                     SubString (au.root_page, 2, 1) +
                     SubString (au.root_page, 1, 1)))'
            When @pageType = 'IAM' Then
                'Select Top 1 @p_fileID = Convert (varchar(6), Convert (int, 
                    SubString (au.first_iam_page, 6, 1) +
                    SubString (au.first_iam_page, 5, 1)))
                , @p_pageID = Convert (varchar(20), Convert (int, 
                     SubString (au.first_iam_page, 4, 1) +
                     SubString (au.first_iam_page, 3, 1) +
                     SubString (au.first_iam_page, 2, 1) +
                     SubString (au.first_iam_page, 1, 1)))'
            End + 
            'From ' + QuoteName(ParseName(@databaseName, 1)) + '.sys.indexes AS i
            Join ' + QuoteName(ParseName(@databaseName, 1)) + '.sys.partitions AS p
                On i.[object_id] = p.[object_id]
                And i.index_id = p.index_id
            Join ' + QuoteName(ParseName(@databaseName, 1)) + '.sys.system_internals_allocation_units AS au
                On p.hobt_id = au.container_id
            Where p.[object_id] = Object_ID(@p_tableName)
                And au.first_page > 0x000000000000 ' 
                + Case When @indexName Is Null 
                    Then ';' 
                    Else 'And i.name = @p_indexName;' End;

            Set @sqlParameters = '@p_tableName varchar(128)
                                , @p_indexName varchar(128)
                                , @p_fileID int OUTPUT
                                , @p_pageID int OUTPUT';
            
            Execute sp_executeSQL @sqlStatement
                        , @sqlParameters
                        , @p_tableName = @tableName
                        , @p_indexName = @indexName
                        , @p_fileID = @fileID OUTPUT
                        , @p_pageID = @pageID OUTPUT;

            End
            Else
            Begin
                Select @fileID = @fileNumber
                    , @pageID = @pageNumber;
            End;

        DBCC TraceOn (3604);
        DBCC Page (@databaseName, @fileID, @pageID, @printOption);
        DBCC TraceOff (3604);

    End Try
    Begin Catch
    
        Print @errorMessage;
    
    End Catch;

    Set NoCount Off;
    Return 0;
End
Go

Set Quoted_Identifier Off;
Go