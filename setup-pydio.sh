#!/bin/sh

set -e
#set -x

# Load our environment.
PYDIO_CONFIG_DIR=/pydio-config
PYDIO_CONFIG_FILE=${PYDIO_CONFIG_DIR}/pydio-env.sh
[ -f "$PYDIO_CONFIG_FILE" ] && . "$PYDIO_CONFIG_FILE"

SED="sed -i -e"

nginx_cfg_modify()
{
    echo "$3: Setting '$1' to '$2' ..."
    ${SED} -i -e "s/\(.*\s*$1\s*.*\).*/$1 $2; # Changed for Pydio/g" $3
}

nginx_cfg_delete()
{
    echo "$2: Deleting '$1' ..."
    ${SED} -i -e "/\s*$1\s*.*/d" $2
}

phpfpm_cfg_modify()
{
    echo "$3: Setting '$1' to '$2' ..."
    ${SED} "s/\(.*\s*$1\s*=.*\).*/$1 = $2 ; Changed for Pydio/g" $3
}

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
        NGINX_SITE_PYDIO=/etc/nginx/sites-enabled/pydio
        # Turn off SSL.
        nginx_cfg_modify "listen" "80" "$NGINX_SITE_PYDIO"
        nginx_cfg_modify "ssl" "off"   "$NGINX_SITE_PYDIO"
        nginx_cfg_delete "ssl_.*"      "$NGINX_SITE_PYDIO"
    fi

    # Configure NginX.
    NGINX_CONF=/etc/nginx/nginx.conf
    nginx_cfg_modify "keepalive_timeout" "2"       "$NGINX_CONF"
    nginx_cfg_modify "client_max_body_size" "100m" "$NGINX_CONF"
    nginx_cfg_modify "server_tokens" "off"         "$NGINX_CONF"

    # Configure php-fpm.
    PHP_FPM_PHP_INI=/etc/php5/fpm/php.ini
    phpfpm_cfg_modify "output_buffering" "off"   "$PHP_FPM_PHP_INI"
    phpfpm_cfg_modify "cgi.fix_pathinfo" "0"     "$PHP_FPM_PHP_INI"
    phpfpm_cfg_modify "upload_max_filesize" "1G" "$PHP_FPM_PHP_INI"
    phpfpm_cfg_modify "post_max_size" "1G"       "$PHP_FPM_PHP_INI"

    # Patch php5-fpm configuration so that it does not daemonize itself. This is
    # needed so that runit can watch its state and restart it if it crashes etc.
    PHP_FPM_CONF=/etc/php5/fpm/php-fpm.conf
    php-fpm_cfg_modify "daemonize" "no"           "$PHP_FPM_PHP_INI"

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
}

write_config()
{
    echo "Writing configuration to: $PYDIO_CONFIG_FILE"
    echo "PYDIO_HOST=$PYDIO_HOST"               >> ${PYDIO_CONFIG_FILE}
    echo "PYDIO_SSL_ENABLED=$PYDIO_SSL_ENABLED" >> ${PYDIO_CONFIG_FILE}
    echo "PYDIO_CORE_PATH=$PYDIO_CORE_PATH"     >> ${PYDIO_CONFIG_FILE}
    echo "PYDIO_LANG=$PYDIO_LANG"               >> ${PYDIO_CONFIG_FILE}
    echo "VIRTUAL_HOST=$VIRTUAL_HOST"           >> ${PYDIO_CONFIG_FILE}
}

while [ $# != 0 ]; do
    CUR_PARM="$1"
    shift
    case "$CUR_PARM" in
        --initial)
            SCRIPT_WRITE_CONFIG=1
            ;;
        --start)
            SCRIPT_START=1
            ;;
        *)
            ;;
    esac
done

setup_pydio
setup_database
setup_nginx

# Do we need to write the configuration file because we don't have one yet?
if [ ! -f "$PYDIO_CONFIG_FILE" ]; then
    SCRIPT_WRITE_CONFIG=1
if

if [ "$SCRIPT_WRITE_CONFIG" = "1" ]; then
    write_config
fi

if [ -n "$SCRIPT_START" ]; then
    pydio-start
fi
