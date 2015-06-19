/**********************************************************************************************************

    NAME:           teradata_ddl_generator.sql

    SYNOPSIS:       Generates Teradata DDL using SQL Server metadata

    DEPENDENCIES:   The following dependencies are required to execute this script:
                    - SQL Server 2005 or newer

    AUTHOR:         Michelle Ufford, http://sqlfool.com
    
    CREATED:        2012-05-17
    
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
    , @TeradataDatabase     VARCHAR(30)     = 'mufford'
    , @TeradataTable        VARCHAR(30)     = NULL -- Will generate if you leave NULL


-- Script-defined variables -- 

DECLARE @columnList TABLE (columnID INT);
DECLARE @TeradataTableName VARCHAR(60);

IF @TeradataTable IS NULL
    SET @TeradataTableName = @TeradataDatabase + '.tmp_' + SUBSTRING(@tableName,PATINDEX('%.%',@tableName)+1,26);
ELSE 
    SET @TeradataTableName = @TeradataDatabase + '.' + @TeradataTable;

DECLARE 
      @schemaStatement      NVARCHAR(MAX) = 'CREATE TABLE ' + @TeradataTableName + '('
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
            @schemaStatement = @schemaStatement + ',';
    END

    SELECT @schemaStatement = @schemaStatement + '"' + c.name + '" ' 
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

    DELETE FROM @columnList WHERE columnID = @currentID;

END;

SELECT @schemaStatement + ');' AS 'Execute this statement in Teradata to create the table:'