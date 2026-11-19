#!/bin/bash
################################################################################
# Program : mrs_monochrome.sh
# Author  : Portfolio Demo
# Desc    : Automated monochrome inventory file processing
#
# IMPORTANT:
# - Portfolio/demo template only. Configure all environment values before use.
# - Do not place passwords, server addresses, or production paths in this file.
# - Use an approved secure file-transfer method (prefer SFTP where available).
################################################################################

# Load environment-specific settings.
# Copy environment.example.sh to environment.sh and configure it locally.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/environment.sh" ]; then
    . "${SCRIPT_DIR}/environment.sh"
else
    echo "[ERROR] Missing scripts/environment.sh"
    echo "Copy environment.example.sh to environment.sh and configure it."
    exit 1
fi

: "${MMHOME:?MMHOME is not configured}"
: "${DB_CONNECT:?DB_CONNECT is not configured}"
: "${FTP_HOST:?FTP_HOST is not configured}"
: "${FTP_USER:?FTP_USER is not configured}"
: "${FTP_REMOTE_IN:?FTP_REMOTE_IN is not configured}"
: "${FTP_REMOTE_ARCHIVE:?FTP_REMOTE_ARCHIVE is not configured}"
: "${FTP_REMOTE_OUT:?FTP_REMOTE_OUT is not configured}"

MRS_DIR="${MMHOME}/data/MRS_MONOCHROME/in"
MRS_ARCH_DIR="${MMHOME}/data/MRS_MONOCHROME/archive"
MRS_OUT_DIR="${MMHOME}/data/MRS_MONOCHROME/out"

CTL_FILE="mrs_monochrome.ctl"
FILE_LIST="${MRS_DIR}/mrs_monochrome_files.txt"

mkdir -p "${MRS_DIR}" "${MRS_ARCH_DIR}" "${MRS_OUT_DIR}"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

get_file() {
    # FTP is retained only as a placeholder to mirror the demonstrated flow.
    # For production, use your organization's approved SFTP client/workflow.
    ftp -inv "${FTP_HOST}" <<EOF
user ${FTP_USER}
cd ${FTP_REMOTE_IN}
lcd ${MRS_DIR}
mget mrs_monochrome_*.csv
quit
EOF
}

send_result_file() {
    local input_file="$1"
    local result_file="RESULT_${input_file}"

    if [ -f "${MRS_OUT_DIR}/${result_file}" ]; then
        log "Sending result file: ${result_file}"
        ftp -inv "${FTP_HOST}" <<EOF
user ${FTP_USER}
cd ${FTP_REMOTE_OUT}
lcd ${MRS_OUT_DIR}
put ${result_file}
quit
EOF
    else
        log "[WARNING] Result file not found: ${MRS_OUT_DIR}/${result_file}"
    fi
}

clear_temp() {
    sqlplus -s "${DB_CONNECT}" <<'SQL'
WHENEVER SQLERROR EXIT SQL.SQLCODE
BEGIN
    DELETE FROM MRS_DEMO.MRS_MONOCHROME_UPLOAD_TMP;
    COMMIT;
END;
/
EXIT;
SQL
}

insert_staging() {
    local input_file="$1"

    sqlplus -s "${DB_CONNECT}" <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON
DECLARE
    l_result BOOLEAN;
    l_error_message VARCHAR2(32767);
BEGIN
    l_error_message := NULL;
    l_result := MRS_DEMO.MRS_MONOCHROME_UPLOAD.INSERT_STAGING(
        P_FILENAME      => '${input_file}',
        O_ERROR_MESSAGE => l_error_message
    );

    IF l_error_message IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE(l_error_message);
    END IF;

    IF NOT l_result THEN
        RAISE_APPLICATION_ERROR(-20001, 'Inventory processing failed');
    END IF;
END;
/
EXIT;
SQL
}

cd "${MRS_DIR}" || exit 1

# Retrieve inbound files.
get_file

# Build a list of files to process.
find "${MRS_DIR}" -maxdepth 1 -type f -name 'mrs_monochrome_*.csv' -printf '%f\n' \
    | sort > "${FILE_LIST}"

if [ ! -s "${FILE_LIST}" ]; then
    log "No mrs_monochrome CSV files found."
    exit 0
fi

while IFS= read -r input_file; do
    [ -n "${input_file}" ] || continue
    [ -f "${MRS_DIR}/${input_file}" ] || continue

    log "Processing ${input_file}"

    if ! clear_temp; then
        log "[ERROR] Failed to clear temporary staging table."
        exit 1
    fi

    # Generate SQL*Loader control file for the current input file.
    cat > "${MRS_DIR}/${CTL_FILE}" <<EOF
OPTIONS (SKIP=1)
LOAD DATA
INTO TABLE MRS_DEMO.MRS_MONOCHROME_UPLOAD_TMP
APPEND
FIELDS TERMINATED BY "," OPTIONALLY ENCLOSED BY '"' TRAILING NULLCOLS
(
    FILENAME CONSTANT "${input_file}",
    SHOP_CODE,
    DATA_TYPE,
    DATA_VALUE,
    CLUSTER_CODE
)
EOF

    # Load the CSV into the temporary staging table.
    sqlldr "${DB_CONNECT}" \
        control="${MRS_DIR}/${CTL_FILE}" \
        log="${MRS_DIR}/${input_file}.log" \
        bad="${MRS_DIR}/${input_file}.bad" \
        data="${MRS_DIR}/${input_file}"
    load_status=$?

    if [ "${load_status}" -ne 0 ]; then
        log "[ERROR] SQL*Loader failed for ${input_file} (exit ${load_status})."
        continue
    fi

    # Execute the Oracle PL/SQL package.
    if ! insert_staging "${input_file}"; then
        log "[ERROR] PL/SQL processing failed for ${input_file}."
        continue
    fi

    # Send generated result file when it exists.
    send_result_file "${input_file}"

    # Archive the processed input file locally.
    mv -- "${MRS_DIR}/${input_file}" "${MRS_ARCH_DIR}/"
    log "Archived ${input_file}"

done < "${FILE_LIST}"

log "Inventory file processing completed."
