/**********************************************************************************************************

    NAME:           bcp_script_generator.sql

    SYNOPSIS:       Generates bcp scripts using SQL Server metadata

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

DECLARE @tableToBCP NVARCHAR(128)   = 'sandbox.dbo.example_table'
    , @Top          VARCHAR(10)     = NULL -- Leave NULL for all rows
    , @Delimiter    VARCHAR(4)      = '|'
    , @UseNULL      BIT             = 1
    , @OverrideChar CHAR(1)         = '~'
    , @MaxDop       CHAR(1)         = '1'
    , @Directory    VARCHAR(256)    = 'D:\dba\mufford\scripts';


-- Script-defined variables -- 

DECLARE @columnList TABLE (columnID INT);

DECLARE @bcpStatement NVARCHAR(MAX) = 'BCP "SELECT '
    , @currentID INT
    , @firstID INT;

INSERT INTO @columnList
SELECT column_id 
FROM sys.columns 
WHERE object_id = OBJECT_ID(@tableToBCP)
ORDER BY column_id;

IF @Top IS NOT NULL
    SET @bcpStatement = @bcpStatement + 'TOP (' + @Top + ') ';

SELECT @firstID = MIN(columnID) FROM @columnList;

WHILE EXISTS(SELECT * FROM @columnList)
BEGIN

    SELECT @currentID = MIN(columnID) FROM @columnList;

    IF @currentID <> @firstID
        SET @bcpStatement = @bcpStatement + ',';

    SELECT @bcpStatement = @bcpStatement + 
                            CASE 
                                WHEN user_type_id IN (231, 167, 175, 239) 
                                THEN 'CASE WHEN ' + name + ' = '''' THEN ' 
                                    + CASE 
                                        WHEN is_nullable = 1 THEN 'NULL' 
                                        ELSE '''' + REPLICATE(@OverrideChar, max_length) + ''''
                                      END
                                    + ' WHEN ' + name + ' LIKE ''%' + @Delimiter + '%'''
                                        + ' OR ' + name + ' LIKE ''%'' + CHAR(9) + ''%''' -- tab
                                        + ' OR ' + name + ' LIKE ''%'' + CHAR(10) + ''%''' -- line feed
                                        + ' OR ' + name + ' LIKE ''%'' + CHAR(13) + ''%''' -- carriage return
                                        + ' THEN ' 
                                        + CASE 
                                            WHEN is_nullable = 1 THEN 'NULL' 
                                            ELSE '''' + REPLICATE(@OverrideChar, max_length) + ''''
                                          END
                                    + ' ELSE ' + name + ' END' 
                                ELSE name 
                            END 
    FROM sys.columns 
    WHERE object_id = OBJECT_ID(@tableToBCP)
        AND column_id = @currentID;

    DELETE FROM @columnList WHERE columnID = @currentID;


END;

SET @bcpStatement = @bcpStatement + ' FROM ' + @tableToBCP 
    + ' WITH (NOLOCK) OPTION (MAXDOP 1);" queryOut '
    + @Directory + REPLACE(@tableToBCP, '.', '_') + '.dat -S' + @@SERVERNAME
    + ' -T -t"' + @Delimiter + '" -c -C;'

SELECT @bcpStatement;