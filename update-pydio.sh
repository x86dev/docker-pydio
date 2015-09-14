#!/bin/sh
set -e
#set -x

# Load our environment.
PYDIO_CONFIG_DIR=/pydio-config
PYDIO_CONFIG_FILE=${PYDIO_CONFIG_DIR}/pydio-env.sh
[ -f "$PYDIO_CONFIG_FILE" ] && . "$PYDIO_CONFIG_FILE"

update_pydio()
{
    echo "Updating: Pydio"

    PYDIO_BOOT_CONF_DIR=${PYDIO_CORE_PATH}/plugins/boot.conf
    PYDIO_BOOTSTRAP_JSON=${PYDIO_BOOT_CONF_DIR}/bootstrap.json

    # Pre-configure Pydio.
    [ ! -d ${PYDIO_BOOT_CONF_DIR} ] && mkdir -p ${PYDIO_BOOT_CONF_DIR}
    cp -f /srv/pydio-bootstrap.json ${PYDIO_BOOT_CONF_DIR}/bootstrap.json

    return

    # Setup DB access in bootstrap config.
    # Note: This must be done here because the DB host's IP could have changed!
    if [ -z "$DB_USER" ]; then
        DB_USER=pydio
    fi
    sed -i -e "s/%DB_PYDIO_USER%/$DB_USER/g"     ${PYDIO_BOOTSTRAP_JSON}
    if [ -z "$DB_PASS" ]; then
        DB_PASS=pydio
    fi
    sed -i -e "s/%DB_PYDIO_PASSWORD%/$DB_PASS/g" ${PYDIO_BOOTSTRAP_JSON}
    if [ -z "$DB_HOST" ]; then
        DB_HOST=localhost
    fi
    sed -i -e "s/%DB_PYDIO_HOST%/$DB_HOST/g"     ${PYDIO_BOOTSTRAP_JSON}

    # Create some files which indicate that Pydio has been installed.
    PYDIO_CACHE_PATH=${PYDIO_CORE_PATH}/data/cache
    ( [ ! -f "$PYDIO_CACHE_PATH/admin_counted" ]    && echo "true" > "$PYDIO_CACHE_PATH/admin_counted" )    || :
    ( [ ! -f "$PYDIO_CACHE_PATH/diag_result.php" ]  && touch "$PYDIO_CACHE_PATH/diag_result.php" )          || :
    ( [ ! -f "$PYDIO_CACHE_PATH/first_run_passed" ] && echo "true" > "$PYDIO_CACHE_PATH/first_run_passed" ) || :
}

update_common()
{
    # Apply ownership of /var/www to www-data.
    chown www-data:www-data -R ${PYDIO_CORE_PATH}

    # Access rights.
    chmod -R u=rwX,go=rX ${PYDIO_CORE_PATH}
    chmod -R u=rwX,go=rX ${PYDIO_CORE_PATH}/data/files/
    chmod -R u=rwX,go=rX ${PYDIO_CORE_PATH}/data/personal/
}

echo "Update: Stopping all ..."
supervisorctl stop all
update_pydio
update_common
echo "Update: Done."
