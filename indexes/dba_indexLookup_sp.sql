If ObjectProperty(Object_ID('dbo.dba_indexLookup_sp'), N'IsProcedure') Is Null
Begin
    Execute ('Create Procedure dbo.dba_indexLookup_sp As Print ''Hello World!''')
    RaisError('Procedure dbo.dba_indexLookup_sp created.', 10, 1);
End;
Go

Set ANSI_Nulls On;
Set Ansi_Padding On;
Set Ansi_Warnings On;
Set ArithAbort On;
Set Concat_Null_Yields_Null On;
Set NoCount On;
Set Numeric_RoundAbort Off;
Set Quoted_Identifier On;
Go

Alter Procedure dbo.dba_indexLookup_sp

        /* Declare Parameters */
        @tableName  varchar(128)  =  Null
As
/**********************************************************************************************************

    NAME:           dba_indexLookup_sp

    SYNOPSIS:       Retrieves index information for the specified table name.

    DEPENDENCIES:   The following dependencies are required to execute this script:
                    - SQL Server 2005 or newer

    NOTES:          If the tableName is left null, it will return index information 
                    for all tables and indexes.

    AUTHOR:         Michelle Ufford, http://sqlfool.com
    
    CREATED:        2008-10-28
    
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

Begin

    Declare @objectID int;

    If @tableName Is Not Null
        Set @objectID = Object_ID(@tableName);

    With indexCTE(partition_scheme_name
                , partition_function_name
                , data_space_id)
    As (
        Select sps.name
            , spf.name
            , sps.data_space_id
        From sys.partition_schemes As sps
        Join sys.partition_functions As spf
            On sps.function_id = spf.function_id
    )

    Select st.name As 'table_name'
        , IsNull(ix.name, '') As 'index_name'
        , ix.object_id
        , ix.index_id
		, Cast(
            Case When ix.index_id = 1 
                    Then 'clustered' 
                When ix.index_id =0
                    Then 'heap'
                Else 'nonclustered' End
			+ Case When ix.ignore_dup_key <> 0 
                Then ', ignore duplicate keys' 
                    Else '' End
			+ Case When ix.is_unique <> 0 
                Then ', unique' 
                    Else '' End
			+ Case When ix.is_primary_key <> 0 
                Then ', primary key' Else '' End As varchar(210)
            ) As 'index_description'
        , IsNull(Replace( Replace( Replace(
            (   
                Select c.name As 'columnName'
                From sys.index_columns As sic
                Join sys.columns As c 
                    On c.column_id = sic.column_id 
                    And c.object_id = sic.object_id
                Where sic.object_id = ix.object_id
                    And sic.index_id = ix.index_id
                    And is_included_column = 0
                Order By sic.index_column_id
                For XML Raw)
                , '"/><row columnName="', ', ')
                , '<row columnName="', '')
                , '"/>', ''), '')
            As 'indexed_columns'
        , IsNull(Replace( Replace( Replace(
            (   
                Select c.name As 'columnName'
                From sys.index_columns As sic
                Join sys.columns As c 
                    On c.column_id = sic.column_id 
                    And c.object_id = sic.object_id
                Where sic.object_id = ix.object_id
                    And sic.index_id = ix.index_id
                    And is_included_column = 1
                Order By sic.index_column_id
                For XML Raw)
                , '"/><row columnName="', ', ')
                , '<row columnName="', '')
                , '"/>', ''), '')
            As 'included_columns'
        , IsNull(cte.partition_scheme_name, '') As 'partition_scheme_name'
        , Count(partition_number) As 'partition_count'
        , Sum(rows) As 'row_count'
    From sys.indexes As ix
    Join sys.partitions As sp
        On ix.object_id = sp.object_id
        And ix.index_id = sp.index_id
    Join sys.tables As st
        On ix.object_id = st.object_id
    Left Join indexCTE As cte
        On ix.data_space_id = cte.data_space_id
    Where ix.object_id = IsNull(@objectID, ix.object_id)
    Group By st.name
        , IsNull(ix.name, '')
        , ix.object_id
        , ix.index_id
		, Cast(
            Case When ix.index_id = 1 
                    Then 'clustered' 
                When ix.index_id =0
                    Then 'heap'
                Else 'nonclustered' End
			+ Case When ix.ignore_dup_key <> 0 
                Then ', ignore duplicate keys' 
                    Else '' End
			+ Case When ix.is_unique <> 0 
                Then ', unique' 
                    Else '' End
			+ Case When ix.is_primary_key <> 0 
                Then ', primary key' Else '' End As varchar(210)
            )
        , IsNull(cte.partition_scheme_name, '')
        , IsNull(cte.partition_function_name, '')
    Order By table_name
        , index_id;

    Set NoCount Off;
    Return 0;
End
Go

Set Quoted_Identifier Off;
Go
