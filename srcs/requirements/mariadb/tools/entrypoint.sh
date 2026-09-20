#!/bin/bash
set -e

# Read secrets safely
if [ -f "${DB_PASSWORD_FILE}" ]; then
    DB_PASS="$(tr -d '\r\n' < "${DB_PASSWORD_FILE}")"
else
    echo "[ERROR] Database password secret not found at ${DB_PASSWORD_FILE}"
    exit 1
fi

if [ -f "${DB_ROOT_PASSWORD_FILE}" ]; then
    DB_ROOT_PASS="$(tr -d '\r\n' < "${DB_ROOT_PASSWORD_FILE}")"
else
    echo "[ERROR] Database root password secret not found at ${DB_ROOT_PASSWORD_FILE}"
    exit 1
fi

# Initialize database if not already initialized
if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
    echo "[INFO] Database '${MYSQL_DATABASE}' not found. Initializing..."
    
    if [ ! -d "/var/lib/mysql/mysql" ]; then
        echo "[INFO] Initializing MariaDB system tables..."
        mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null
    fi

    echo "[INFO] Configuring MariaDB users and database via bootstrap..."
    mariadbd --user=mysql --datadir=/var/lib/mysql --bootstrap <<EOF
USE mysql;
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF

    echo "[INFO] MariaDB initialization complete."
fi

echo "[INFO] Launching MariaDB as PID 1..."
exec mariadbd --user=mysql --datadir=/var/lib/mysql --console
