#!/usr/bin/env bash
set -euo pipefail
test "${GLPI_LAB_CONFIRM:-}" = isolated-synthetic
test "${MARIADB_DATABASE:-}" = branef_glpi_lab
if [ ! -f config/config_db.php ]; then
  runuser -u www-data -- php bin/console db:install --no-interaction --force \
    --db-host=lab-db --db-name=branef_glpi_lab --db-user=glpi --db-password="$LAB_DB_PASSWORD" --default-language=en_GB
fi
php /usr/local/lib/branef-glpi-bootstrap.php
touch config/lab-ready
exec apache2-foreground
