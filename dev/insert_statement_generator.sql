/**********************************************************************************************************

    NAME:           insert_statement_generator.sql

    SYNOPSIS:       Generates insert statements for Teradata using SQL Server metadata.
                    This is useful for easily migrating small tables (i.e. < 1000 rows) 
                    from SQL Server to Teradata. DO NOT use on large tables. 

    DEPENDENCIES:   The following dependencies are required to execute this script:
                    - SQL Server 2005 or newer

    AUTHOR:         Michelle Ufford, http://sqlfool.com
    
    CREATED:        2012-07-26
    
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

-- User-defined variables --
DECLARE 
      @tableName            NVARCHAR(128)   = 'dbo.example_table'
    , @Top                  VARCHAR(10)     = 1000 -- Leave NULL for all rows
    , @Execute              BIT             = 1
    , @GenerateSchema       BIT             = 1
    , @GenerateTruncate     BIT             = 1
    , @TeradataDatabase     VARCHAR(30)     = 'mufford'
    , @TeradataTable        VARCHAR(30)     = NULL -- Will generate if you leave NULL

-- Script-defined variables -- 

DECLARE @columnList TABLE (columnID INT);
DECLARE @TeradataTableName VARCHAR(60);

IF @TeradataTable IS NULL
    SET @TeradataTableName = @TeradataDatabase + '.tmp_' + SUBSTRING(@tableName,PATINDEX('%.%',@tableName)+1,26);
ELSE 
    SET @TeradataTableName = @TeradataDatabase + '.' + @TeradataTable;

DECLARE @insertStatement    NVARCHAR(MAX) = '' --= 'SELECT '
    , @columnStatement      NVARCHAR(MAX) = 'INSERT INTO ' + @TeradataTableName + ' ('
    , @schemaStatement      NVARCHAR(MAX) = 'CREATE TABLE ' + @TeradataTableName + '('
    , @currentID            INT
    , @firstID              INT;

INSERT INTO @columnList
SELECT column_id 
FROM sys.columns 
WHERE object_id = OBJECT_ID(@tableName)
ORDER BY column_id;

SELECT @firstID = MIN(columnID) FROM @columnList;

WHILE EXISTS(SELECT * FROM @columnList)
BEGIN

    SELECT @currentID = MIN(columnID) FROM @columnList;

    IF @currentID <> @firstID
    BEGIN
        SELECT 
              @columnStatement = @columnStatement + ','
            , @schemaStatement = @schemaStatement + ','
            , @insertStatement = @insertStatement + '+'',''+';
    END

    SELECT @columnStatement = @columnStatement + '"' + SUBSTRING(name, 1, 30) + '"'
    FROM sys.columns
    WHERE object_id = OBJECT_ID(@tableName)
        AND column_id = @currentID;

    SELECT @schemaStatement = @schemaStatement + '"' + SUBSTRING(c.name, 1, 30) + '" ' 
        + CASE 
            WHEN t.name = 'BIT'                             THEN 'BYTEINT'
            WHEN t.name = 'TINYINT'                         THEN 'SMALLINT'
            WHEN t.name = 'UNIQUEIDENTIFIER'                THEN 'CHAR(38)'
            WHEN t.name = 'DATETIME'                        THEN 'TIMESTAMP(3)'
            WHEN t.name = 'MONEY'                           THEN 'DECIMAL(18,4)'
            WHEN t.name = 'XML'                             THEN 'CLOB'
            WHEN t.name IN ('SMALLDATETIME', 'DATETIME2')   THEN 'TIMESTAMP(0)'
            WHEN t.name IN ('NVARCHAR','NCHAR')
                THEN SUBSTRING(t.name, 2, 10) + '(' + CAST(c.max_length / 2 AS VARCHAR(4)) + ') CHARACTER SET UNICODE NOT CASESPECIFIC'
            WHEN t.name IN ('VARCHAR','CHAR')
                THEN t.name + '(' + CAST(c.max_length AS VARCHAR(4)) + ')'
            ELSE t.name
        END
        + CASE
            WHEN c.is_nullable = 1 THEN ' NULL'
            ELSE ' NOT NULL'
        END
    FROM sys.columns    AS c
    JOIN sys.types      AS t
        ON c.system_type_id = t.system_type_id
    WHERE c.object_id = OBJECT_ID(@tableName)
        AND c.column_id = @currentID;

    SELECT DISTINCT @insertStatement = @insertStatement 
            + 'CASE WHEN ' + QUOTENAME(c.name) + ' IS NULL THEN ''NULL'' ELSE ' + 
            + CASE 
                WHEN t.name IN ('tinyint','smallint','int','real','float','bit','decimal','numeric','smallmoney','bigint') /* number-based columns */
                    THEN 'CAST(' + QUOTENAME(c.name) + ' AS VARCHAR(' + CAST(c.precision AS VARCHAR(10)) + '))' 
                WHEN t.name IN ('datetime', 'date', 'datetime2', 'smalldatetime') /* date-based columns */
                    THEN '''''''''+' + 'CONVERT(VARCHAR(23),' + QUOTENAME(c.name) + ',126)' + '+'''''''''
                WHEN t.name IN ('uniqueidentifier') /* guid columns */
                    THEN '''''''''+' + 'CAST(' + QUOTENAME(c.name) + ' AS CHAR(36))' + '+'''''''''
                WHEN t.name IN ('XML') /* xml columns */
                    THEN '''''''''+' + 'CAST(' + QUOTENAME(c.name) + ' AS VARCHAR(MAX))' + '+'''''''''
                ELSE '''''''''+REPLACE(' + QUOTENAME(c.name) + ','''''''','''''''''''')+''''''''' --'''+''''''+''' /* character-based columns */
              END 
                + ' END '
    FROM sys.columns    AS c
    JOIN sys.types      AS t
        ON c.system_type_id = t.system_type_id
    WHERE c.object_id = OBJECT_ID(@tableName)
        AND c.column_id = @currentID;

    DELETE FROM @columnList WHERE columnID = @currentID;

END;

SET @insertStatement = 'SELECT ' + CASE WHEN @Top IS NOT NULL THEN 'TOP (' + @Top + ') ' ELSE '' END + '''' + @columnStatement + ') VALUES (''+' + @insertStatement + '+'');'' FROM ' + @tableName + ' WITH (NOLOCK);';

IF @GenerateSchema = 1
    SELECT @schemaStatement + ');' AS 'Execute this statement in Teradata to create the table:'

IF @GenerateTruncate = 1
    SELECT 'DELETE FROM ' + @TeradataTableName + ';' AS 'Execute this statement in Teradata to truncate the table:'

IF @Execute = 1
    EXECUTE sp_executeSQL @insertStatement;
ELSE
    SELECT @insertStatement AS 'Execute this statement in SQL Server to generate commands:';
