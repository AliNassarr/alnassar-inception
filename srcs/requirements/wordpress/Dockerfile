FROM alpine:3.23

RUN apk update && apk upgrade && apk add --no-cache \
    php83 \
    php83-fpm \
    php83-mysqli \
    php83-json \
    php83-curl \
    php83-dom \
    php83-exif \
    php83-fileinfo \
    php83-mbstring \
    php83-openssl \
    php83-xml \
    php83-zip \
    php83-phar \
    php83-iconv \
    mariadb-client \
    curl \
    bash

# Symlink php83 to php so WP-CLI can execute php
RUN ln -s /usr/bin/php83 /usr/bin/php

# Increase PHP memory limit for WP-CLI
RUN echo "memory_limit = 512M" > /etc/php83/conf.d/99-memory-limit.ini

# Download and install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp

# Ensure www-data user exists
RUN adduser -u 82 -D -S -G www-data www-data 2>/dev/null || true

COPY conf/www.conf /etc/php83/php-fpm.d/www.conf
COPY tools/setup.sh /usr/local/bin/setup.sh

RUN chmod +x /usr/local/bin/setup.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/setup.sh"]
