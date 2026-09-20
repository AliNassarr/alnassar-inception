#!/bin/bash
set -e

# Increase PHP memory limit for WP-CLI operations
export WP_CLI_PHP_ARGS="-d memory_limit=512M"

# Validate admin username does NOT contain admin/Admin
if echo "${WP_ADMIN_USER}" | grep -iq "admin"; then
    echo "[ERROR] Admin username ('${WP_ADMIN_USER}') must not contain 'admin' or 'Admin'!"
    exit 1
fi

# Read secrets safely
if [ -f "${DB_PASSWORD_FILE}" ]; then
    DB_PASS="$(tr -d '\r\n' < "${DB_PASSWORD_FILE}")"
else
    echo "[ERROR] Database password secret not found at ${DB_PASSWORD_FILE}"
    exit 1
fi

if [ -f "${WP_ADMIN_PASSWORD_FILE}" ]; then
    WP_ADMIN_PASS="$(tr -d '\r\n' < "${WP_ADMIN_PASSWORD_FILE}")"
else
    echo "[ERROR] WordPress admin password secret not found at ${WP_ADMIN_PASSWORD_FILE}"
    exit 1
fi

if [ -f "${WP_USER_PASSWORD_FILE}" ]; then
    WP_USER_PASS="$(tr -d '\r\n' < "${WP_USER_PASSWORD_FILE}")"
else
    echo "[ERROR] WordPress user password secret not found at ${WP_USER_PASSWORD_FILE}"
    exit 1
fi

# Wait for MariaDB to become ready
echo "[INFO] Waiting for MariaDB at ${MYSQL_HOST}:3306..."
until mariadb -h "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"${DB_PASS}" -e "SELECT 1;" > /dev/null 2>&1; do
    sleep 2
done
echo "[INFO] MariaDB is available!"

# Download WordPress core if missing
if [ ! -f "/var/www/html/wp-config-sample.php" ] && [ ! -f "/var/www/html/wp-config.php" ]; then
    echo "[INFO] Downloading WordPress core..."
    wp core download --allow-root --path=/var/www/html
fi

# Configure wp-config.php if missing
if [ ! -f "/var/www/html/wp-config.php" ]; then
    echo "[INFO] Creating wp-config.php..."
    wp config create \
        --allow-root \
        --path=/var/www/html \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASS}" \
        --dbhost="${MYSQL_HOST}:3306"
fi

# Install WordPress and create users if not already installed
if ! wp core is-installed --allow-root --path=/var/www/html > /dev/null 2>&1; then
    echo "[INFO] Installing WordPress..."
    wp core install \
        --allow-root \
        --path=/var/www/html \
        --url="${WP_URL}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASS}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email

    echo "[INFO] Creating regular user '${WP_USER}'..."
    wp user create \
        "${WP_USER}" \
        "${WP_USER_EMAIL}" \
        --role="${WP_USER_ROLE:-author}" \
        --user_pass="${WP_USER_PASS}" \
        --allow-root \
        --path=/var/www/html
    echo "[INFO] WordPress installation complete!"
fi

# Fix permissions
chown -R www-data:www-data /var/www/html

echo "[INFO] Launching PHP-FPM 8.3 as PID 1..."
exec php-fpm83 -F
