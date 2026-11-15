# Laravel Docker / Sail to Native macOS Migrator

A non-destructive helper script that inspects an existing Laravel Sail or Docker Compose repository and prepares `.env.native` + `.stratos.json` for native macOS development without Docker Desktop VM overhead.

## Usage

Run against any Laravel project directory:

```bash
curl -fsSLO https://stratosapp.dev/tools/laravel-docker-to-native-migrator.sh
bash laravel-docker-to-native-migrator.sh /path/to/laravel-app
```

## What It Does (Non-Destructively)

1. **Detects PHP & Services**: Reads `docker-compose.yml` / `compose.yaml` and `composer.json` to detect the PHP version (`8.1`–`8.5`) and active services (`mysql`, `mariadb`, `pgsql`, `redis`, `mailpit`/`mailhog`, `meilisearch`, `minio`).
2. **Generates `.env.native`**: Creates a side-by-side `.env.native` file (leaving your existing `.env` untouched) with Docker hostnames remapped to `127.0.0.1` and `MAIL_PORT=1025`.
3. **Creates `.stratos.json`**: Generates a `.stratos.json` project descriptor (if absent) with your `.test` domain and PHP version.

## Switching Steps Printed by the Script

1. `./vendor/bin/sail down`
2. `cp .env .env.sail.bak && cp .env.native .env`
3. Open the folder in [Stratos for macOS](https://stratosapp.dev/download/) for native Nginx + PHP-FPM + `.test` HTTPS + MailCatcher (`port 1025`).
