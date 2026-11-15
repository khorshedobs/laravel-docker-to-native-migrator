#!/usr/bin/env bash
set -uo pipefail

# laravel-docker-to-native-migrator.sh
# Non-destructive helper that inspects a Laravel Sail / Docker Compose project
# and generates .env.native + .stratos.json for native macOS development.
# Part of Stratos open-source sidecar tools (https://stratosapp.dev)

TARGET_INPUT="${1:-.}"
if [ ! -d "$TARGET_INPUT" ]; then
  echo "Error: Directory not found: ${TARGET_INPUT}" >&2
  exit 1
fi

PROJECT_DIR="$(cd "$TARGET_INPUT" && pwd)"
PROJECT_SLUG="$(basename "$PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/^-*//; s/-*$//')"
if [ -z "$PROJECT_SLUG" ]; then
  PROJECT_SLUG="laravel-app"
fi
LOCAL_DOMAIN="${PROJECT_SLUG}.test"

COMPOSE_FILE=""
for CANDIDATE in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
  if [ -f "${PROJECT_DIR}/${CANDIDATE}" ]; then
    COMPOSE_FILE="${PROJECT_DIR}/${CANDIDATE}"
    break
  fi
done

COMPOSER_FILE="${PROJECT_DIR}/composer.json"
ENV_FILE="${PROJECT_DIR}/.env"

# Detect PHP version (8.1 - 8.5), defaulting to 8.3
DETECTED_PHP="8.3"
if [ -n "$COMPOSE_FILE" ]; then
  COMPOSE_PHP="$(grep -oE 'sail-8\.[1-5]|PHP_VERSION["=: ]+8\.[1-5]|php[:-]8\.[1-5]' "$COMPOSE_FILE" | grep -oE '8\.[1-5]' | head -n 1 || true)"
  if [ -n "$COMPOSE_PHP" ]; then
    DETECTED_PHP="$COMPOSE_PHP"
  fi
fi

if [ "$DETECTED_PHP" = "8.3" ] && [ -f "$COMPOSER_FILE" ]; then
  COMPOSER_PHP="$(grep -E '"php"' "$COMPOSER_FILE" | grep -oE '8\.[1-5]' | head -n 1 || true)"
  if [ -n "$COMPOSER_PHP" ]; then
    DETECTED_PHP="$COMPOSER_PHP"
  fi
fi

# Detect Docker services in compose file
SERVICES_FOUND=()
if [ -n "$COMPOSE_FILE" ]; then
  for SVC in mysql mariadb pgsql postgres redis mailpit mailhog meilisearch minio; do
    if grep -qiE "(^|\s|image:.*)${SVC}" "$COMPOSE_FILE"; then
      SERVICES_FOUND+=("$SVC")
    fi
  done
fi

echo "================================================================"
echo " Laravel Docker / Sail -> Native macOS Migrator"
echo " Project: ${PROJECT_DIR}"
echo " Domain:  https://${LOCAL_DOMAIN}"
echo " PHP:     ${DETECTED_PHP}"
if [ -n "$COMPOSE_FILE" ]; then
  echo " Compose: $(basename "$COMPOSE_FILE")"
else
  echo " Compose: Not found (proceeding with .env / composer.json inspection)"
fi
if [ "${#SERVICES_FOUND[@]}" -gt 0 ]; then
  echo " Services: ${SERVICES_FOUND[*]}"
else
  echo " Services: none detected in compose file"
fi
echo "================================================================"
echo ""

# Write non-destructive .env.native
NATIVE_ENV="${PROJECT_DIR}/.env.native"
if [ -f "$ENV_FILE" ]; then
  tmp_env="$(mktemp)"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      DB_HOST=*)
        val="${line#DB_HOST=}"
        case "$val" in
          mysql|mariadb|pgsql|postgres|db|database)
            echo "DB_HOST=127.0.0.1" >> "$tmp_env"
            ;;
          *)
            echo "$line" >> "$tmp_env"
            ;;
        esac
        ;;
      REDIS_HOST=*)
        val="${line#REDIS_HOST=}"
        case "$val" in
          redis|sail-redis)
            echo "REDIS_HOST=127.0.0.1" >> "$tmp_env"
            ;;
          *)
            echo "$line" >> "$tmp_env"
            ;;
        esac
        ;;
      MAIL_HOST=*)
        val="${line#MAIL_HOST=}"
        case "$val" in
          mailpit|mailhog|smtp)
            echo "MAIL_HOST=127.0.0.1" >> "$tmp_env"
            ;;
          *)
            echo "$line" >> "$tmp_env"
            ;;
        esac
        ;;
      MAIL_PORT=*)
        echo "MAIL_PORT=1025" >> "$tmp_env"
        ;;
      MEMCACHED_HOST=*)
        val="${line#MEMCACHED_HOST=}"
        if [ "$val" = "memcached" ]; then
          echo "MEMCACHED_HOST=127.0.0.1" >> "$tmp_env"
        else
          echo "$line" >> "$tmp_env"
        fi
        ;;
      MEILISEARCH_HOST=*)
        if echo "$line" | grep -qi "meilisearch"; then
          echo "MEILISEARCH_HOST=http://127.0.0.1:7700" >> "$tmp_env"
        else
          echo "$line" >> "$tmp_env"
        fi
        ;;
      *)
        echo "$line" >> "$tmp_env"
        ;;
    esac
  done < "$ENV_FILE"
  mv "$tmp_env" "$NATIVE_ENV"
  echo "OK: Wrote ${NATIVE_ENV} (original .env untouched)."
else
  echo "INFO: No .env found in ${PROJECT_DIR}; skipped .env.native generation."
fi

# Write .stratos.json if absent
STRATOS_CFG="${PROJECT_DIR}/.stratos.json"
if [ ! -f "$STRATOS_CFG" ]; then
  SERVICES_JSON=""
  if [ "${#SERVICES_FOUND[@]}" -gt 0 ]; then
    for s in "${SERVICES_FOUND[@]}"; do
      if [ -n "$SERVICES_JSON" ]; then
        SERVICES_JSON="${SERVICES_JSON}, "
      fi
      SERVICES_JSON="${SERVICES_JSON}\"${s}\""
    done
  fi
  cat > "$STRATOS_CFG" <<JSON
{
  "name": "${PROJECT_SLUG}",
  "domain": "${LOCAL_DOMAIN}",
  "php": "${DETECTED_PHP}",
  "services": [${SERVICES_JSON}]
}
JSON
  echo "OK: Wrote ${STRATOS_CFG}."
else
  echo "INFO: Existing ${STRATOS_CFG} preserved."
fi

echo ""
echo "Next steps to switch off Docker Desktop / Sail:"
echo "  1. ./vendor/bin/sail down"
if [ -f "$NATIVE_ENV" ]; then
  echo "  2. cp .env .env.sail.bak && cp .env.native .env"
else
  echo "  2. Create .env with DB_HOST=127.0.0.1 and REDIS_HOST=127.0.0.1"
fi
echo "  3. Add ${PROJECT_DIR} in Stratos (PHP ${DETECTED_PHP}, instant https://${LOCAL_DOMAIN} SSL, MailCatcher on :1025)"
echo "     Download Stratos Free -> https://stratosapp.dev/download/"
