# Process Flow

```text
Remote inbound CSV
       |
       v
Shell script: retrieve and detect files
       |
       v
Clear temporary staging table
       |
       v
Generate SQL*Loader control file
       |
       v
SQL*Loader -> MRS_MONOCHROME_UPLOAD_TMP
       |
       v
PL/SQL: INSERT_STAGING
       |
       +--> Validate SHOP / DEP / ITEM_DATA
       |
       +--> Invalid rows: mark error and generate result
       |
       +--> Valid rows: MERGE into MRS_MAPPING_MONOCHROME
       |
       v
GEN_RESULT_MONOCHROME_UPLOAD (UTL_FILE)
       |
       v
Shell script: send result if present
       |
       v
Archive input file locally
```

The diagram describes the intended workflow represented by the sample files. Configure and test all external dependencies before execution.
