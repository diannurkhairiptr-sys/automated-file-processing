# MRS Monochrome Inventory File Processing

Portfolio demonstration of an automated CSV-to-Oracle inventory workflow using Shell Scripting, SQL*Loader, and PL/SQL.

## Project workflow

1. Retrieve `mrs_monochrome_*.csv` input files from a remote inbound folder.
2. Check for files to process.
3. Clear the demo temporary staging table.
4. Generate a SQL*Loader control file and load CSV rows into the staging table.
5. Call `MRS_DEMO.MRS_MONOCHROME_UPLOAD.INSERT_STAGING`.
6. Validate shop, department (`DEP`), and item (`ITEM_DATA`) references.
7. Merge valid records into the demo mapping table (update existing rows or insert new rows).
8. Generate a pipe-delimited result file using `UTL_FILE`.
9. Send the result file when present and archive the input file locally.

## Repository structure

- `scripts/mrs_monochrome.sh` — shell workflow.
- `scripts/environment.example.sh` — example configuration with placeholders only.
- `sql/01_package_spec.sql` — package specification.
- `sql/02_package_body.sql` — package body.
- `docs/process_flow.md` — process explanation.

## Important setup notes

This is an anonymized portfolio template, not a production-ready or tested deployment package. It uses fictional schema/object names under `MRS_DEMO`. Create the required demo tables, sequence, reference tables, Oracle DIRECTORY object, and grants before compiling or running it.

The shell script expects Oracle client tools (`sqlplus`, `sqlldr`) and a configured environment. Copy `scripts/environment.example.sh` to `scripts/environment.sh` and set values locally. Do not commit `environment.sh`.

The transfer commands are illustrative. Prefer SFTP or an approved managed file-transfer solution for real environments. Do not put passwords in scripts or command-line arguments.

## Expected database objects

The package references these illustrative objects:

- `MRS_DEMO.MRS_MONOCHROME_UPLOAD_TMP`
- `MRS_DEMO.MRS_MONOCHROME_UPLOAD_STG`
- `MRS_DEMO.MRS_MONOCHROME_SEQ`
- `MRS_DEMO.MRS_MAPPING_MONOCHROME`
- `MRS_DEMO.SHOP`
- `MRS_DEMO.DEP`
- `MRS_DEMO.ITEM_DATA`
- Oracle DIRECTORY object `MRS_MONOCHROME_OUT_DIR`

The staging table is expected to contain the columns used by the package, including `GENERATE_DATETIME`. The temporary table is expected to contain `FILENAME`, `SHOP_CODE`, `DATA_TYPE`, `DATA_VALUE`, `CLUSTER_CODE`, and `CREATE_DATETIME`.

## Important implementation notes

- The package uses `DATA_TYPE = 'DEP'` for department validation, following the requested anonymized naming.
- The package uses `UTL_FILE` with an Oracle DIRECTORY object name rather than a hard-coded server filesystem path.
- Review transaction boundaries, error handling, file-transfer exit codes, duplicate handling, and concurrency before any real deployment.
- The shell script intentionally does not delete remote inbound files automatically. Confirm transfer success and archive policy before adding remote deletion.
- The package function returns BOOLEAN; calling it from PL/SQL is supported, but BOOLEAN cannot be selected directly from SQL.
