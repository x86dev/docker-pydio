#!/bin/sh

set -e
#set -x

# Load our environment.
PYDIO_CONFIG_DIR=/pydio-config
PYDIO_CONFIG_FILE=${PYDIO_CONFIG_DIR}/pydio-env.sh
[ -f "$PYDIO_CONFIG_FILE" ] && . "$PYDIO_CONFIG_FILE"

setup_nginx()
{
    if [ -z "$PYDIO_HOST" ]; then
        PYDIO_HOST=localhost
    fi

    echo "Setting up NginX for '$PYDIO_HOST' ..."

    if [ "$PYDIO_SSL_ENABLED" = "1" ]; then
        # Only generate the certificates once!
        if [ ! -f "$PYDIO_CONFIG_DIR/pydio.key" ]; then
            echo "Generating webserver certificates ..."
            # Generate the TLS certificate for our Pydio server instance.
            openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
                -subj "/C=US/ST=World/L=World/O=$PYDIO_HOST/CN=$PYDIO_HOST" \
                -keyout "$PYDIO_CONFIG_DIR/pydio.key" \
                -out "$PYDIO_CONFIG_DIR/pydio.crt"
        fi
        chmod 600 "$PYDIO_CONFIG_DIR/pydio.key"
        chmod 600 "$PYDIO_CONFIG_DIR/pydio.crt"
    else
        # Turn off SSL.
        sed -i -e "s/\s*listen\s*443\s*.*;$/\tlisten 80;/g" /etc/nginx/sites-enabled/pydio
        sed -i -e "s/\s*ssl\s*on\s*;/\tssl off;/g" /etc/nginx/sites-enabled/pydio
        sed -i -e "/\s*ssl_.*/d" /etc/nginx/sites-enabled/pydio
    fi

    # Configure NginX.
    NGINX_CONF=/etc/nginx/nginx.conf
    sed -i -e "s/\s*keepalive_timeout\s*65/\tkeepalive_timeout 2/" ${NGINX_CONF}
    sed -i -e "/\s*client_max_body_size.*/d" ${NGINX_CONF}
    sed -i -e "s/\s*keepalive_timeout 2/keepalive_timeout 2;\n\tclient_max_body_size 100m/" ${NGINX_CONF}
    sed -i -e "s/.*server_tokens\s.*/server_tokens off;/g" ${NGINX_CONF}

    # Configure Nginx so that is doesn't show its version number in the HTTP headers.
    sed -i -e "s/.*server_tokens.*/server_tokens off;/g" ${NGINX_CONF}

    # Configure php-fpm.
    PHP_FPM_PHP_INI=/etc/php5/fpm/php.ini
    sed -i -e "s/output_buffering\s*=\s*4096/output_buffering = off/g" ${PHP_FPM_PHP_INI}
    sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" ${PHP_FPM_PHP_INI}
    sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 1G/g" ${PHP_FPM_PHP_INI}
    sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 1G/g" ${PHP_FPM_PHP_INI}

    # Patch php5-fpm configuration so that it does not daemonize itself. This is
    # needed so that runit can watch its state and restart it if it crashes etc.
    PHP_FPM_CONF=/etc/php5/fpm/php-fpm.conf
    sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" ${PHP_FPM_CONF}

    # Enable mcrypt.
    php5enmod mcrypt

    # Save all into our persistent environment.
    echo "PYDIO_HOST=$PYDIO_HOST"               >> ${PYDIO_CONFIG_FILE}
    echo "PYDIO_SSL_ENABLED=$PYDIO_SSL_ENABLED" >> ${PYDIO_CONFIG_FILE}
}

setup_database()
{
    if [ -z "$DB_HOST" ]; then
        DB_HOST=localhost
        DB_BIND_ADR=0.0.0.0
    else
        DB_BIND_ADR=${DB_HOST}
    fi
    if [ -z "$DB_USER" ]; then
        DB_USER=pydio
        DB_PASS=pydio
    fi

    echo "Setting up database: $DB_HOST ($DB_BIND_ADR) for user '$DB_USER' ..."

    # Configure MySQL DB.
    sed -i -e"s/^bind-address\s*=\s*127.0.0.1/bind-address = $DB_BIND_ADR/" /etc/mysql/my.cnf
    service mysql start
    mysql -uroot -e "CREATE DATABASE IF NOT EXISTS pydio;"
    ## @todo Add "CREATE USER IF NOT EXISTS" (since MySQL 5.7.6).
    #        This might fail if the user already exists, so guard this explicitly.
    mysql -uroot -e "CREATE USER '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASS';" || :
    mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASS' WITH GRANT OPTION;"
    mysql -uroot -e "FLUSH PRIVILEGES;"

    # Insert scheme.
    # Taken from: https://github.com/pydio/pydio-core/blob/develop/dist/docker/create.mysql
    #mysql --user="$DB_USER" --password="$DB_PASS" pydio < /srv/pydio-scheme.mysql

    service mysql stop

    # Set access rights.
    chown -R mysql.mysql /var/lib/mysql/pydio
}

setup_pydio()
{
    echo "Setting up Pydio ..."

    if [ -z "$PYDIO_CORE_PATH" ]; then
        PYDIO_CORE_PATH=/var/www/pydio-core
    fi
    PYDIO_BOOTSTRAP_CONF=${PYDIO_CORE_PATH}/conf/bootstrap_conf.php

    # Force Pydio to use SSL in case we have a virtual host defined.
    if [ "$PYDIO_SSL_ENABLED" = "1" ]; then
        PYDIO_FORCE_SSL_REDIRECT=1
    fi
    if [ -n "$VIRTUAL_HOST" ]; then
        PYDIO_FORCE_SSL_REDIRECT=1
    fi
    #if [ "$PYDIO_FORCE_SSL_REDIRECT" = "1" ]; then
    #    sed -i -e"s/\/\/define(\"AJXP_FORCE_SSL_REDIRECT\", true);/define(\"AJXP_FORCE_SSL_REDIRECT\", true);/g" ${PYDIO_BOOTSTRAP_CONF}
    #fi

    # Set language.
    if [ -z "$PYDIO_LANG" ]; then
        PYDIO_LANG="en_US.UTF-8"
    fi
    echo "Using language: $PYDIO_LANG"
    sed -i -e"/\s*\"AJXP_LOCALE\".*/d" ${PYDIO_BOOTSTRAP_CONF}
    echo "define(\"AJXP_LOCALE\", \"$PYDIO_LANG\");" >> ${PYDIO_BOOTSTRAP_CONF}

    # Save all into our persistent environment.
    echo "PYDIO_CORE_PATH=$PYDIO_CORE_PATH" >> ${PYDIO_CONFIG_FILE}
    echo "PYDIO_LANG=$PYDIO_LANG"           >> ${PYDIO_CONFIG_FILE}
    echo "VIRTUAL_HOST=$VIRTUAL_HOST"       >> ${PYDIO_CONFIG_FILE}
}

if [ -z "$PYDIO_SETUP_DONE" ]; then
    setup_pydio
    setup_database
    setup_nginx

    # Mark the setup as being complete.
    echo "PYDIO_SETUP_DONE=1" >> ${PYDIO_CONFIG_FILE}
fi

if [ "$1" = "--start" ]; then
    pydio-start
fi
