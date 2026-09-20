FROM alpine:3.23

RUN apk update && apk upgrade && apk add --no-cache \
    mariadb \
    mariadb-client \
    bash

RUN mkdir -p /var/lib/mysql /run/mysqld && \
    chown -R mysql:mysql /var/lib/mysql /run/mysqld && \
    chmod 777 /run/mysqld

COPY conf/my.cnf /etc/my.cnf.d/mariadb-server.cnf
RUN chmod 644 /etc/my.cnf.d/mariadb-server.cnf

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3306

USER mysql

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
