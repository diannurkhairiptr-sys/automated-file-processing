CREATE OR REPLACE PACKAGE BODY MRS_DEMO.MRS_MONOCHROME_UPLOAD
AS
    FUNCTION INSERT_STAGING (
        P_FILENAME        IN     VARCHAR2,
        O_ERROR_MESSAGE   IN OUT VARCHAR2
    ) RETURN BOOLEAN
    IS
        V_FILE_ID      NUMBER;
        V_ERROR_COUNT  NUMBER := 0;
        V_GEN_OK       BOOLEAN;
    BEGIN
        SELECT MRS_DEMO.MRS_MONOCHROME_SEQ.NEXTVAL
          INTO V_FILE_ID
          FROM DUAL;

        INSERT INTO MRS_DEMO.MRS_MONOCHROME_UPLOAD_STG (
            FILE_ID,
            FILENAME,
            SHOP_CODE,
            DATA_TYPE,
            DATA_VALUE,
            CLUSTER_CODE,
            CREATE_DATETIME,
            PROCESS_DATETIME,
            PROCESS_IND,
            ERROR_MESSAGE
        )
        SELECT
            V_FILE_ID,
            T.FILENAME,
            T.SHOP_CODE,
            T.DATA_TYPE,
            T.DATA_VALUE,
            T.CLUSTER_CODE,
            T.CREATE_DATETIME,
            NULL,
            CASE
                WHEN S.SHOP IS NULL
                  OR (T.DATA_TYPE = 'DEP' AND D.DEP IS NULL)
                  OR (T.DATA_TYPE = 'ITEM' AND I.ITEM IS NULL)
                THEN 'E'
                ELSE 'N'
            END,
            CASE
                WHEN S.SHOP IS NULL
                    THEN 'SHOP CODE ' || T.SHOP_CODE || ' NOT VALID'
                WHEN T.DATA_TYPE = 'DEP' AND D.DEP IS NULL
                    THEN 'DEP ' || T.DATA_VALUE || ' NOT VALID'
                WHEN T.DATA_TYPE = 'ITEM' AND I.ITEM IS NULL
                    THEN 'ITEM ' || T.DATA_VALUE || ' NOT VALID'
                ELSE NULL
            END
        FROM MRS_DEMO.MRS_MONOCHROME_UPLOAD_TMP T
        LEFT JOIN MRS_DEMO.SHOP S
               ON T.SHOP_CODE = S.SHOP
        LEFT JOIN MRS_DEMO.DEP D
               ON T.DATA_VALUE = D.DEP
              AND T.DATA_TYPE = 'DEP'
        LEFT JOIN MRS_DEMO.ITEM_DATA I
               ON T.DATA_VALUE = I.ITEM
              AND T.DATA_TYPE = 'ITEM'
        WHERE T.FILENAME = P_FILENAME;

        SELECT COUNT(1)
          INTO V_ERROR_COUNT
          FROM MRS_DEMO.MRS_MONOCHROME_UPLOAD_STG
         WHERE FILE_ID = V_FILE_ID
           AND PROCESS_IND = 'E'
           AND FILENAME = P_FILENAME;

        IF V_ERROR_COUNT > 0 THEN
            UPDATE MRS_DEMO.MRS_MONOCHROME_UPLOAD_STG
               SET PROCESS_IND = 'E',
                   PROCESS_DATETIME = SYSDATE
             WHERE FILE_ID = V_FILE_ID
               AND FILENAME = P_FILENAME;

            COMMIT;

            V_GEN_OK := GEN_RESULT_MONOCHROME_UPLOAD(
                P_FILENAME, O_ERROR_MESSAGE
            );

            O_ERROR_MESSAGE := 'File processing cancelled due to invalid data.';
            RETURN FALSE;
        ELSE
            MERGE INTO MRS_DEMO.MRS_MAPPING_MONOCHROME M
            USING (
                SELECT SHOP_CODE, DATA_TYPE, DATA_VALUE, CLUSTER_CODE
                  FROM MRS_DEMO.MRS_MONOCHROME_UPLOAD_STG
                 WHERE FILE_ID = V_FILE_ID
                   AND PROCESS_IND = 'N'
                   AND FILENAME = P_FILENAME
            ) S
            ON (
                   M.SHOP       = S.SHOP_CODE
               AND M.DATA_TYPE  = S.DATA_TYPE
               AND M.DATA_VALUE = S.DATA_VALUE
            )
            WHEN MATCHED THEN
                UPDATE SET
                    M.CLUSTER_ID       = S.CLUSTER_CODE,
                    M.STATUS_IND       = 'A',
                    M.INSERT_TIMESTAMP = SYSDATE
            WHEN NOT MATCHED THEN
                INSERT (
                    SHOP,
                    DATA_TYPE,
                    DATA_VALUE,
                    CLUSTER_ID,
                    STATUS_IND,
                    INSERT_TIMESTAMP
                )
                VALUES (
                    S.SHOP_CODE,
                    S.DATA_TYPE,
                    S.DATA_VALUE,
                    S.CLUSTER_CODE,
                    'A',
                    SYSDATE
                );

            UPDATE MRS_DEMO.MRS_MONOCHROME_UPLOAD_STG
               SET PROCESS_IND = 'P',
                   PROCESS_DATETIME = SYSDATE
             WHERE FILE_ID = V_FILE_ID
               AND PROCESS_IND = 'N'
               AND FILENAME = P_FILENAME;

            COMMIT;

            V_GEN_OK := GEN_RESULT_MONOCHROME_UPLOAD(
                P_FILENAME, O_ERROR_MESSAGE
            );

            IF NOT V_GEN_OK THEN
                RETURN FALSE;
            END IF;

            RETURN TRUE;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            O_ERROR_MESSAGE := 'Error INSERT_STAGING: ' || SQLERRM;
            RETURN FALSE;
    END INSERT_STAGING;


    FUNCTION GEN_RESULT_MONOCHROME_UPLOAD (
        P_FILENAME        IN     VARCHAR2,
        O_ERROR_MESSAGE   IN OUT VARCHAR2
    ) RETURN BOOLEAN
    IS
        CURSOR BULK_FILE_HEADER IS
            SELECT DISTINCT FILENAME
              FROM MRS_DEMO.MRS_MONOCHROME_UPLOAD_STG
             WHERE PROCESS_IND IN ('P', 'E')
               AND FILENAME = P_FILENAME
               AND GENERATE_DATETIME IS NULL;

        CURSOR BULK_PROCESS_RESULT (G_FILENAME VARCHAR2) IS
            SELECT FILE_ID,
                   FILENAME,
                   SHOP_CODE,
                   DATA_TYPE,
                   DATA_VALUE,
                   CLUSTER_CODE,
                   CREATE_DATETIME,
                   PROCESS_DATETIME,
                   PROCESS_IND,
                   ERROR_MESSAGE
              FROM MRS_DEMO.MRS_MONOCHROME_UPLOAD_STG
             WHERE PROCESS_IND IN ('P', 'E')
               AND GENERATE_DATETIME IS NULL
               AND FILENAME = G_FILENAME;

        -- Configure this directory as an Oracle DIRECTORY object in your demo DB.
        L_FILE_DIR   VARCHAR2(128) := 'MRS_MONOCHROME_OUT_DIR';
        L_FILE       UTL_FILE.FILE_TYPE;
        L_FILENAME   VARCHAR2(300);
        L_BUFFER     VARCHAR2(4000);
    BEGIN
        FOR C IN BULK_FILE_HEADER LOOP
            L_FILENAME := 'RESULT_' || C.FILENAME;
            L_FILE := UTL_FILE.FOPEN(L_FILE_DIR, L_FILENAME, 'W');

            L_BUFFER :=
                'FILE_ID|FILENAME|SHOP_CODE|DATA_TYPE|DATA_VALUE|CLUSTER_CODE'
                || '|CREATE_DATETIME|PROCESS_DATETIME|PROCESS_IND|ERROR_MESSAGE';

            UTL_FILE.PUT_LINE(L_FILE, L_BUFFER);

            FOR F IN BULK_PROCESS_RESULT(C.FILENAME) LOOP
                L_BUFFER :=
                       F.FILE_ID
                    || '|' || F.FILENAME
                    || '|' || F.SHOP_CODE
                    || '|' || F.DATA_TYPE
                    || '|' || F.DATA_VALUE
                    || '|' || TRIM(TRANSLATE(F.CLUSTER_CODE, CHR(10)||CHR(13), '  '))
                    || '|' || TO_CHAR(F.CREATE_DATETIME, 'YYYY-MM-DD HH24:MI:SS')
                    || '|' || TO_CHAR(F.PROCESS_DATETIME, 'YYYY-MM-DD HH24:MI:SS')
                    || '|' || F.PROCESS_IND
                    || '|' || F.ERROR_MESSAGE;

                UTL_FILE.PUT_LINE(L_FILE, L_BUFFER);
            END LOOP;

            UTL_FILE.FCLOSE(L_FILE);

            UPDATE MRS_DEMO.MRS_MONOCHROME_UPLOAD_STG
               SET GENERATE_DATETIME = SYSDATE
             WHERE FILENAME = C.FILENAME;

            COMMIT;
        END LOOP;

        RETURN TRUE;

    EXCEPTION
        WHEN OTHERS THEN
            IF UTL_FILE.IS_OPEN(L_FILE) THEN
                UTL_FILE.FCLOSE(L_FILE);
            END IF;
            O_ERROR_MESSAGE := 'Error in GEN_RESULT_MONOCHROME_UPLOAD: ' || SQLERRM;
            RETURN FALSE;
    END GEN_RESULT_MONOCHROME_UPLOAD;

END MRS_MONOCHROME_UPLOAD;
/
