#!/usr/bin/env bash
# configuresql.sh - Configure Azure SQL DB: create ToDo table, enable change tracking, add UAMI user
# Usage: ./configuresql.sh

set -euo pipefail

# Get environment values from azd
output=$(azd env get-values)

# Initialize variables
SQL_SERVER=""
SQL_DATABASE=""
UAMI_CLIENT_ID=""
UAMI_PRINCIPAL_ID=""
UAMI_NAME=""

# Parse the output to get the resource names
while IFS= read -r line; do
    if [[ $line == AZURE_SQL_SERVER_NAME* ]]; then
        SQL_SERVER=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
    elif [[ $line == AZURE_SQL_DATABASE_NAME* ]]; then
        SQL_DATABASE=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
    elif [[ $line == USER_ASSIGNED_IDENTITY_CLIENT_ID* ]]; then
        UAMI_CLIENT_ID=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
    elif [[ $line == USER_ASSIGNED_IDENTITY_PRINCIPAL_ID* ]]; then
        UAMI_PRINCIPAL_ID=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
    elif [[ $line == USER_ASSIGNED_IDENTITY_NAME* ]]; then
        UAMI_NAME=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
    fi
done <<< "$output"

# Use static SQL files in the same folder as this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Download and install sqlcmd if not present in $SCRIPT_DIR
SQLCMD_BASEURL="https://github.com/microsoft/go-sqlcmd/releases/download/"
SQLCMD_VERSION="v1.8.2"
if [ ! -x "$SCRIPT_DIR/sqlcmd" ]; then
    echo "sqlcmd not found in $SCRIPT_DIR. Downloading..."
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    if [[ "$OS" == "darwin" ]]; then
        # macOS
        if [[ "$ARCH" == "arm64" ]]; then
            URL="${SQLCMD_BASEURL}${SQLCMD_VERSION}/sqlcmd-darwin-arm64.tar.bz2"
        else
            URL="${SQLCMD_BASEURL}${SQLCMD_VERSION}/sqlcmd-vdarwin-x64.tar.bz2"
        fi
    elif [[ "$OS" == "linux" ]]; then
        if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
            URL="${SQLCMD_BASEURL}${SQLCMD_VERSION}/sqlcmd-linux-arm64.tar.bz2"
        else
            URL="${SQLCMD_BASEURL}${SQLCMD_VERSION}/sqlcmd-linux-amd64.tar.bz2"
        fi
    elif [[ "$OS" == "windows_nt" || "$OS" == "msys" || "$OS" == "cygwin" ]]; then
        if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
            URL="${SQLCMD_BASEURL}${SQLCMD_VERSION}/sqlcmd-windows-amd64.zip"
        elif [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
            URL="${SQLCMD_BASEURL}${SQLCMD_VERSION}/sqlcmd-windows-arm.zip"
        else
            echo "Unsupported Windows architecture: $ARCH"
            exit 1
        fi
    else
        echo "Unsupported OS: $OS"
        exit 1
    fi
    echo "Downloading sqlcmd from: $URL"
    cd "$SCRIPT_DIR"
    curl -L "$URL" -o sqlcmd.tar.bz2
    if [[ "$URL" == *.tar.bz2 ]]; then
        tar xjf sqlcmd.tar.bz2
    elif [[ "$URL" == *.tar.gz ]]; then
        tar xzf sqlcmd.tar.gz
    elif [[ "$URL" == *.zip ]]; then
        unzip sqlcmd.zip
    else
        echo "Unknown archive format for $URL"
        exit 1
    fi
    chmod +x sqlcmd
    cd - > /dev/null
fi

# Run the scripts using sqlcmd from $SCRIPT_DIR
echo "$SCRIPT_DIR/sqlcmd -S $SQL_SERVER -d $SQL_DATABASE -G -i $SCRIPT_DIR/sql_create_table.sql"
"$SCRIPT_DIR/sqlcmd" -S "$SQL_SERVER" -d "$SQL_DATABASE" -G -i "$SCRIPT_DIR/sql_create_table.sql"

echo "$SCRIPT_DIR/sqlcmd -S $SQL_SERVER -d $SQL_DATABASE -G -v SQL_DATABASE=\"$SQL_DATABASE\" -i $SCRIPT_DIR/sql_enable_change_tracking.sql"
"$SCRIPT_DIR/sqlcmd" -S "$SQL_SERVER" -d "$SQL_DATABASE" -G -v SQL_DATABASE="$SQL_DATABASE" -i "$SCRIPT_DIR/sql_enable_change_tracking.sql"

echo "$SCRIPT_DIR/sqlcmd -S $SQL_SERVER -d $SQL_DATABASE -G -v UAMI_NAME=\"$UAMI_NAME\" UAMI_PRINCIPAL_ID=\"$UAMI_PRINCIPAL_ID\" -i $SCRIPT_DIR/sql_add_uami_user.sql"
"$SCRIPT_DIR/sqlcmd" -S "$SQL_SERVER" -d "$SQL_DATABASE" -G -v UAMI_NAME="$UAMI_NAME" UAMI_PRINCIPAL_ID="$UAMI_PRINCIPAL_ID" -i "$SCRIPT_DIR/sql_add_uami_user.sql"

echo "SQL configuration complete."
