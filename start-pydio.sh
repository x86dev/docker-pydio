#!/bin/sh

set -e

# Make sure an old instance of supervisord is not running anymore.
supervisorctl stop all

# Test if need to run the setup (again).
pydio-setup

# Update configuration. This is necessary for entering the current IP + PORT of the database.
pydio-update

# Start supervisord.
# This will start all other dependencies.
supervisord -c /etc/supervisor/supervisord.conf
