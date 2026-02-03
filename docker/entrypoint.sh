#!/bin/ash -e
## check for .env file or symlink and generate app keys if missing
if [ -f /var/www/html/.env ]; then
  echo "external vars exist."
else
  echo "external vars don't exist."
  # webroot .env is symlinked to this path
  touch /laravel_template-data/.env

  ## manually generate a key because key generate --force fails
  if [ -z $APP_KEY ]; then
    echo -e "Generating key."
    APP_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
    echo -e "Generated app key: $APP_KEY"
    echo -e "APP_KEY=$APP_KEY" > /laravel_template-data/.env
  else
    echo -e "APP_KEY exists in environment, using that."
    echo -e "APP_KEY=$APP_KEY" > /laravel_template-data/.env
  fi
fi

mkdir -p /laravel_template-data/storage /var/www/html/storage/logs/supervisord 2>/dev/null

if ! grep -q "APP_KEY=" .env || grep -q "APP_KEY=$" .env; then
  echo "Generating APP_KEY..."
  php artisan key:generate --force
else
  echo "APP_KEY is already set."
fi

# Run database migrations
echo "Running database migrations..."
php artisan migrate --force

# default to nginx not starting
export SUPERVISORD_NGINX=false
export PARSED_LE_EMAIL="email ${LE_EMAIL}"
export PARSED_APP_URL=${APP_URL}

# when running behind a proxy
if [[ ${BEHIND_PROXY} == "true" ]]; then
  echo "running behind proxy"
  echo "listening on port 80 internally"
  export PARSED_LE_EMAIL=""
  export PARSED_APP_URL=":80"
  export PARSED_AUTO_HTTPS="auto_https off"
  export ASSET_URL=${APP_URL}
fi

## disable nginx if SKIP_NGINX is set
if [[ "${SKIP_NGINX:-}" == "true" ]]; then
  echo "Starting PHP-FPM only"
else
  echo "Starting PHP-FPM and Nginx"
  # enable nginx
  export SUPERVISORD_NGINX=true

  # handle trusted proxies for nginx (configuration already in nginx.conf)
  if [[ ! -z ${TRUSTED_PROXIES} ]]; then
    # Note: Nginx trusted proxies are configured in nginx.conf
    echo "Trusted proxies: ${TRUSTED_PROXIES}"
  fi
fi

echo "Starting Supervisord"
exec "$@"