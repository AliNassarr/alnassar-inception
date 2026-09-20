#!/bin/bash
set -euo pipefail

# Increase PHP memory limit for WP-CLI operations
export WP_CLI_PHP_ARGS="-d memory_limit=512M"

# ----- Read env variables -----
MYSQL_HOST="${MYSQL_HOST:?}"
MYSQL_PORT="${MYSQL_PORT:?}"
MYSQL_DATABASE="${MYSQL_DATABASE:?}"
MYSQL_USER="${MYSQL_USER:?}"
DB_PASS=$(tr -d '\r\n' < "${MYSQL_PASSWORD_FILE:?}")

WP_TITLE="${WP_TITLE:?}"
WP_URL="${WP_URL:?}"
WP_ADMIN_USER="${WP_ADMIN_USER:?}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:?}"
WP_ADMIN_PASS=$(tr -d '\r\n' < "${WP_ADMIN_PASSWORD_FILE:?}")
WP_USER="${WP_USER:?}"
WP_USER_EMAIL="${WP_USER_EMAIL:?}"
WP_USER_PASS=$(tr -d '\r\n' < "${WP_USER_PASSWORD_FILE:?}")

# Validate admin username does not contain admin/Admin
if echo "${WP_ADMIN_USER}" | grep -iq "admin"; then
    echo "[ERROR] Admin username ('${WP_ADMIN_USER}') must not contain 'admin' or 'Admin'!"
    exit 1
fi

# Wait for database
echo "Waiting for database..."
for i in {1..30}; do
  if mariadb -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" -p"${DB_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then
    echo "Database connected!"
    break
  fi
  sleep 2
done

# Basic WordPress setup
if [ ! -f "wp-includes/version.php" ]; then
  echo "Downloading WordPress..."
  curl -fsSL https://wordpress.org/latest.tar.gz | tar -xz --strip-components=1
fi

if [ ! -f "wp-config.php" ]; then
  echo "Creating wp-config.php..."
  cp wp-config-sample.php wp-config.php
  sed -i "s/database_name_here/${MYSQL_DATABASE}/g" wp-config.php
  sed -i "s/username_here/${MYSQL_USER}/g" wp-config.php
  sed -i "s/password_here/${DB_PASS}/g" wp-config.php
  sed -i "s/localhost/${MYSQL_HOST}:${MYSQL_PORT}/g" wp-config.php
fi

# Install WordPress only if not installed
if ! wp core is-installed --allow-root --path=/var/www/html >/dev/null 2>&1; then
  echo "Installing WordPress..."
  wp core install \
    --url="${WP_URL}" \
    --title="${WP_TITLE}" \
    --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASS}" \
    --admin_email="${WP_ADMIN_EMAIL}" \
    --skip-email \
    --allow-root

  # Create regular user
  echo "Creating regular user: ${WP_USER}..."
  wp user create "${WP_USER}" "${WP_USER_EMAIL}" --role=subscriber --user_pass="${WP_USER_PASS}" --allow-root || true
  echo "WordPress installation complete!"
else
  echo "WordPress is already installed and configured."
fi

# Set permissions
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

echo "Starting PHP-FPM as PID 1..."
exec php-fpm83 -F
