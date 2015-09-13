#!/bin/sh

set -x

setup_nginx()
{
    if [ -z "$PYDIO_HOST" ]; then
        PYDIO_HOST=localhost
    fi

    echo "Setting up NginX for '$PYDIO_HOST' ..."

    if [ "$PYDIO_SSL_ENABLED" = "1" ]; then
        ## @todo Separate key/crt directories?
        PYDIO_SSL_CERT_PATH=/etc/ssl/private
        if [ ! -f "$PYDIO_SSL_CERT_PATH/pydio.key" ]; then
            # Generate the TLS certificate for our Tiny Tiny RSS server instance.
            openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
                -subj "/C=US/ST=World/L=World/O=$PYDIO_HOST/CN=$PYDIO_HOST" \
                -keyout "$PYDIO_SSL_CERT_PATH/pydio.key" \
                -out "$PYDIO_SSL_CERT_PATH/pydio.crt"
        fi
        chmod 600 "$PYDIO_SSL_CERT_PATH/pydio.key"
        chmod 600 "$PYDIO_SSL_CERT_PATH/pydio.crt"
    else
        # Turn off SSL.
        sed -i -e "s/\s*listen\s*443\s*;/listen 80;/g" /etc/nginx/sites-enabled/pydio
        sed -i -e "s/\s*ssl\s*on\s*;/ssl off;/g" /etc/nginx/sites-enabled/pydio
        sed -i -e "/\s*ssl_*/d" /etc/nginx/sites-enabled/pydio
    fi

    # Configure NginX.
    NGINX_CONF=/etc/nginx/nginx.conf
    sed -i -e"s/\s*keepalive_timeout\s*65/\tkeepalive_timeout 2/" ${NGINX_CONF}
    sed -i -e"/\s*client_max_body_size.*/d" ${NGINX_CONF}
    sed -i -e"s/\s*keepalive_timeout 2/keepalive_timeout 2;\n\tclient_max_body_size 100m/" ${NGINX_CONF}
    sed -i -e "s/\s*server_tokens.*/server_tokens off;/g" ${NGINX_CONF}

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
    mysql -uroot -e "CREATE DATABASE pydio;"
    mysql -uroot -e "CREATE USER '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASS';"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASS' WITH GRANT OPTION;"
    mysql -uroot -e "FLUSH PRIVILEGES;"

    # Set access rights.
    chown -R mysql.mysql /var/lib/mysql/pydio

    # Insert scheme.
    # Taken from: https://github.com/pydio/pydio-core/blob/develop/dist/docker/create.mysql
    #mysql --user="$DB_USER" --password="$DB_PASS" pydio < /srv/pydio-scheme.mysql

    service mysql stop
}

setup_pydio()
{
    echo "Setting up Pydio ..."

    PYDIO_PATH=/var/www/pydio-core
    PYDIO_BOOTSTRAP_CONF=${PYDIO_PATH}/conf/bootstrap_conf.php

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
    if [ "$PYDIO_LANG" = "" ]; then
        PYDIO_LANG="en_US.UTF-8"
    fi

    echo "Using language: $PYDIO_LANG"
    sed -i -e"/\s*\"AJXP_LOCALE\".*/d" ${PYDIO_BOOTSTRAP_CONF}
    echo "define(\"AJXP_LOCALE\", \"$PYDIO_LANG\");" >> ${PYDIO_BOOTSTRAP_CONF}
}

echo "Setup: Installing Pydio ..."
setup_pydio
setup_database
setup_nginx

echo "Setup: Applying updates ..."
/srv/update-pydio.sh

echo "Setup: Done"
