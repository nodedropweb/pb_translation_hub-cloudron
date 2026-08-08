#!/bin/bash

set -eu

chown -R cloudron:cloudron /app/data

echo "Starting Node.js backend"
/usr/local/bin/gosu cloudron:cloudron node /app/code/server/index.js &

echo "Starting Nginx"
exec nginx -g 'daemon off;'
