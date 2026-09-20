#!/bin/bash
set -e

# Generate self-signed SSL/TLS certificate if missing
if [ ! -f "/etc/nginx/ssl/alnassar.crt" ] || [ ! -f "/etc/nginx/ssl/alnassar.key" ]; then
    echo "[INFO] Generating self-signed SSL/TLS certificate for ${DOMAIN_NAME:-alnassar.42.fr}..."
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
        -keyout /etc/nginx/ssl/alnassar.key \
        -out /etc/nginx/ssl/alnassar.crt \
        -subj "/C=FR/ST=Beirut/L=Beirut/O=42/OU=42/CN=${DOMAIN_NAME:-alnassar.42.fr}"
    echo "[INFO] SSL/TLS certificate generated successfully."
fi

echo "[INFO] Launching NGINX as PID 1..."
exec nginx -g "daemon off;"
