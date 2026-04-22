#!/usr/bin/env bash
# =============================================================================
#  new-env.sh — Cria um novo ambiente Docker isolado de forma interativa
#
#  Uso:
#    ./new-env.sh                  (modo interativo)
#    ./new-env.sh --name cliente-x  (pula a pergunta do nome)
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENVS_DIR="$ROOT/envs"
REGISTRY="$ROOT/envs/.registry"

# --- cores -------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}  →${RESET} $*"; }
success() { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}  !${RESET} $*"; }
error()   { echo -e "${RED}  ✗${RESET} $*"; exit 1; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# --- carregar registro de portas já usadas -----------------------------------
mkdir -p "$ENVS_DIR"
touch "$REGISTRY"

port_in_use() {
  grep -q ":$1$" "$REGISTRY" 2>/dev/null || \
  ss -tlnp 2>/dev/null | grep -q ":$1 " || \
  nc -z localhost "$1" 2>/dev/null
}

next_free_port() {
  local p=$1
  while port_in_use "$p"; do (( p++ )); done
  echo "$p"
}

# =============================================================================
echo -e "\n${BOLD}╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║     Novo ambiente Docker isolado     ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"

# --- 1. Nome do ambiente -----------------------------------------------------
header "1. Nome do ambiente"
NAME_ARG=""
for arg in "$@"; do [[ "$arg" == --name=* ]] && NAME_ARG="${arg#--name=}"; done

if [[ -n "$NAME_ARG" ]]; then
  ENV_NAME="$NAME_ARG"
else
  echo "   Será usado como prefixo de containers, volumes e redes."
  read -rp "   Nome (ex: cliente-x, equipe-backend, php74-legado): " ENV_NAME
fi

ENV_NAME="${ENV_NAME// /-}"
ENV_NAME="${ENV_NAME//[^a-zA-Z0-9_-]/}"
ENV_NAME="${ENV_NAME,,}"

[[ -z "$ENV_NAME" ]] && error "Nome não pode ser vazio."
[[ -d "$ENVS_DIR/$ENV_NAME" ]] && error "Ambiente '$ENV_NAME' já existe. Use ./manage.sh para gerenciá-lo."

# --- 2. Versão do PHP --------------------------------------------------------
header "2. Versão do PHP"
echo "   Versões disponíveis:"
echo "   1) PHP 8.4  (mais recente)"
echo "   2) PHP 8.3"
echo "   3) PHP 8.2"
echo "   4) PHP 8.1"
echo "   5) PHP 8.0"
echo "   6) PHP 7.4"
echo "   7) Outra (digitar manualmente)"
read -rp "   Escolha [1-7] (padrão: 1): " PHP_CHOICE
PHP_CHOICE="${PHP_CHOICE:-1}"

case "$PHP_CHOICE" in
  1) PHP_VERSION="8.4" ;;
  2) PHP_VERSION="8.3" ;;
  3) PHP_VERSION="8.2" ;;
  4) PHP_VERSION="8.1" ;;
  5) PHP_VERSION="8.0" ;;
  6) PHP_VERSION="7.4" ;;
  7) read -rp "   Versão PHP (ex: 8.0, 7.3): " PHP_VERSION ;;
  *) PHP_VERSION="8.4" ;;
esac

# --- 3. Banco de dados -------------------------------------------------------
header "3. Banco de dados"
echo "   1) MySQL 8.0"
echo "   2) MySQL 5.7  (para sistemas mais antigos)"
echo "   3) PostgreSQL 16"
echo "   4) PostgreSQL 15"
echo "   5) PostgreSQL 13"
echo "   6) MariaDB 11"
echo "   7) Nenhum"
read -rp "   Escolha [1-7] (padrão: 1): " DB_CHOICE
DB_CHOICE="${DB_CHOICE:-1}"

case "$DB_CHOICE" in
  1) DB_ENGINE="mysql";    DB_IMAGE="mysql:8.0";       DB_PORT_INT=3306; EXT_PDO="pdo_mysql" ;;
  2) DB_ENGINE="mysql";    DB_IMAGE="mysql:5.7";        DB_PORT_INT=3306; EXT_PDO="pdo_mysql" ;;
  3) DB_ENGINE="postgres"; DB_IMAGE="postgres:16-alpine"; DB_PORT_INT=5432; EXT_PDO="pdo_pgsql pgsql" ;;
  4) DB_ENGINE="postgres"; DB_IMAGE="postgres:15-alpine"; DB_PORT_INT=5432; EXT_PDO="pdo_pgsql pgsql" ;;
  5) DB_ENGINE="postgres"; DB_IMAGE="postgres:13-alpine"; DB_PORT_INT=5432; EXT_PDO="pdo_pgsql pgsql" ;;
  6) DB_ENGINE="mysql";    DB_IMAGE="mariadb:11";       DB_PORT_INT=3306; EXT_PDO="pdo_mysql" ;;
  7) DB_ENGINE="none";     DB_IMAGE="";                 DB_PORT_INT=0;    EXT_PDO="" ;;
  *) DB_ENGINE="mysql";    DB_IMAGE="mysql:8.0";        DB_PORT_INT=3306; EXT_PDO="pdo_mysql" ;;
esac

# --- 4. Redis ----------------------------------------------------------------
header "4. Redis"
read -rp "   Incluir Redis? [S/n]: " WANT_REDIS
WANT_REDIS="${WANT_REDIS:-S}"
[[ "$WANT_REDIS" =~ ^[Ss]$ ]] && WITH_REDIS=true || WITH_REDIS=false

# --- 5. Framework / tipo de projeto ------------------------------------------
header "5. Tipo de projeto"
echo "   1) Laravel  (instala via Composer automaticamente)"
echo "   2) Symfony"
echo "   3) Projeto PHP genérico  (sem framework)"
read -rp "   Escolha [1-3] (padrão: 1): " FW_CHOICE
FW_CHOICE="${FW_CHOICE:-1}"
case "$FW_CHOICE" in
  1) FRAMEWORK="laravel"  ;;
  2) FRAMEWORK="symfony"  ;;
  3) FRAMEWORK="generic"  ;;
  *) FRAMEWORK="laravel"  ;;
esac

# --- 6. Node.js --------------------------------------------------------------
header "6. Node.js"
echo "   1) Node 22 LTS  (Vite, compilação de assets)"
echo "   2) Node 20 LTS"
echo "   3) Não incluir"
read -rp "   Escolha [1-3] (padrão: 1): " NODE_CHOICE
NODE_CHOICE="${NODE_CHOICE:-1}"
case "$NODE_CHOICE" in
  1) NODE_VERSION="22"; WITH_NODE=true ;;
  2) NODE_VERSION="20"; WITH_NODE=true ;;
  3) WITH_NODE=false ;;
  *) NODE_VERSION="22"; WITH_NODE=true ;;
esac

# --- 7. Portas ---------------------------------------------------------------
header "7. Portas no host"
SUGGESTED_HTTP=$(next_free_port 8080)
SUGGESTED_DB=$(next_free_port 3306)
[[ "$DB_ENGINE" == "postgres" ]] && SUGGESTED_DB=$(next_free_port 5432)
SUGGESTED_REDIS=$(next_free_port 6379)
SUGGESTED_MAIL=$(next_free_port 8025)

echo "   Sugestões (já verificadas como livres):"
echo "   HTTP:  $SUGGESTED_HTTP"
[[ "$DB_ENGINE" != "none" ]]  && echo "   DB:    $SUGGESTED_DB"
$WITH_REDIS                    && echo "   Redis: $SUGGESTED_REDIS"
echo "   Mail:  $SUGGESTED_MAIL"
echo ""
read -rp "   Usar as sugestões? [S/n]: " USE_SUGGESTED
USE_SUGGESTED="${USE_SUGGESTED:-S}"

if [[ "$USE_SUGGESTED" =~ ^[Ss]$ ]]; then
  PORT_HTTP=$SUGGESTED_HTTP
  PORT_DB=$SUGGESTED_DB
  PORT_REDIS=$SUGGESTED_REDIS
  PORT_MAIL=$SUGGESTED_MAIL
else
  read -rp "   Porta HTTP [$SUGGESTED_HTTP]: " PORT_HTTP
  PORT_HTTP="${PORT_HTTP:-$SUGGESTED_HTTP}"
  if [[ "$DB_ENGINE" != "none" ]]; then
    read -rp "   Porta DB [$SUGGESTED_DB]: "   PORT_DB
    PORT_DB="${PORT_DB:-$SUGGESTED_DB}"
  fi
  if $WITH_REDIS; then
    read -rp "   Porta Redis [$SUGGESTED_REDIS]: " PORT_REDIS
    PORT_REDIS="${PORT_REDIS:-$SUGGESTED_REDIS}"
  fi
  read -rp "   Porta Mailpit [$SUGGESTED_MAIL]: " PORT_MAIL
  PORT_MAIL="${PORT_MAIL:-$SUGGESTED_MAIL}"
fi

# --- 8. Resumo e confirmação -------------------------------------------------
echo ""
echo -e "${BOLD}┌─────────────────────────────────────────┐${RESET}"
echo -e "${BOLD}│  Resumo do ambiente                     │${RESET}"
echo -e "${BOLD}├─────────────────────────────────────────┤${RESET}"
printf   "│  %-12s %-26s │\n" "Nome:"      "$ENV_NAME"
printf   "│  %-12s %-26s │\n" "PHP:"       "$PHP_VERSION-FPM"
[[ "$DB_ENGINE" != "none" ]] && \
printf   "│  %-12s %-26s │\n" "Banco:"     "$DB_IMAGE"
$WITH_REDIS && \
printf   "│  %-12s %-26s │\n" "Redis:"     "redis:7-alpine"
$WITH_NODE && \
printf   "│  %-12s %-26s │\n" "Node:"      "$NODE_VERSION LTS"
printf   "│  %-12s %-26s │\n" "Framework:" "$FRAMEWORK"
printf   "│  %-12s %-26s │\n" "HTTP:"      "localhost:$PORT_HTTP"
[[ "$DB_ENGINE" != "none" ]] && \
printf   "│  %-12s %-26s │\n" "DB host:"   "localhost:$PORT_DB"
$WITH_REDIS && \
printf   "│  %-12s %-26s │\n" "Redis:"     "localhost:$PORT_REDIS"
printf   "│  %-12s %-26s │\n" "Mailpit:"   "localhost:$PORT_MAIL"
echo -e "${BOLD}└─────────────────────────────────────────┘${RESET}"
echo ""
read -rp "  Criar este ambiente? [S/n]: " CONFIRM
CONFIRM="${CONFIRM:-S}"
[[ ! "$CONFIRM" =~ ^[Ss]$ ]] && echo "Cancelado." && exit 0

# =============================================================================
#  GERAÇÃO DOS ARQUIVOS
# =============================================================================
ENV_DIR="$ENVS_DIR/$ENV_NAME"
mkdir -p "$ENV_DIR"/{php,nginx/conf.d,projects}
[[ "$DB_ENGINE" == "mysql"    ]] && mkdir -p "$ENV_DIR/mysql/init"
[[ "$DB_ENGINE" == "postgres" ]] && mkdir -p "$ENV_DIR/postgres/init"

header "Gerando arquivos..."

# --- Dockerfile PHP ----------------------------------------------------------
EXTRA_LIBS="libpng-dev libjpeg62-turbo-dev libfreetype6-dev libonig-dev libxml2-dev libzip-dev libicu-dev libssl-dev"
EXTRA_EXTS="pcntl bcmath gd zip opcache intl xml sockets"
[[ "$DB_ENGINE" == "postgres" ]] && EXTRA_LIBS="$EXTRA_LIBS libpq-dev" && EXTRA_EXTS="$EXTRA_EXTS $EXT_PDO"
[[ "$DB_ENGINE" == "mysql"    ]] && EXTRA_EXTS="$EXTRA_EXTS $EXT_PDO"

REDIS_BLOCK=""
$WITH_REDIS && REDIS_BLOCK='    && pecl install redis \
    && docker-php-ext-enable redis \\'

NODE_BLOCK=""
$WITH_NODE && NODE_BLOCK="
# Node.js $NODE_VERSION
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \\
    && apt-get install -y nodejs \\
    && apt-get clean \\
    && rm -rf /var/lib/apt/lists/*"

cat > "$ENV_DIR/php/Dockerfile" <<DOCKERFILE
FROM php:${PHP_VERSION}-fpm

LABEL environment="${ENV_NAME}"

RUN apt-get update && apt-get install -y --no-install-recommends \\
        git curl unzip zip ${EXTRA_LIBS} \\
    && docker-php-ext-configure gd --with-freetype --with-jpeg \\
    && docker-php-ext-install -j\$(nproc) \\
        mbstring exif ${EXTRA_EXTS} \\
    ${REDIS_BLOCK}
    && apt-get clean \\
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
${NODE_BLOCK}

RUN groupadd -g 1000 www && useradd -u 1000 -g www -m -s /bin/bash www

WORKDIR /var/www
USER www
DOCKERFILE

# --- local.ini ---------------------------------------------------------------
cat > "$ENV_DIR/php/local.ini" <<INI
memory_limit        = 512M
upload_max_filesize = 128M
post_max_size       = 128M
max_execution_time  = 300
display_errors      = On
display_startup_errors = On
error_reporting     = E_ALL
log_errors          = On
date.timezone       = America/Sao_Paulo
opcache.enable      = 1
opcache.validate_timestamps = 1
opcache.revalidate_freq = 0
INI

# --- nginx default.conf ------------------------------------------------------
cat > "$ENV_DIR/nginx/conf.d/default.conf" <<NGINX
server {
    listen 80;
    server_name _;
    root /var/www/default/public;
    index index.php index.html;
    charset utf-8;
    client_max_body_size 128M;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php$ {
        fastcgi_pass ${ENV_NAME}_php:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }
    location ~ /\.(?!well-known).* { deny all; }
}
NGINX

# --- docker-compose.yml ------------------------------------------------------
# Bloco do banco de dados
DB_SERVICE=""
DB_DEPENDS=""
DB_ENV_PHP=""
DB_VOLUME_ENTRY=""
DB_VOLUME_MOUNT=""
DB_HEALTH=""

if [[ "$DB_ENGINE" == "mysql" ]]; then
  DB_NAME_VAR="${ENV_NAME//-/_}_db"
  DB_VOLUME_NAME="${ENV_NAME}_db_data"
  DB_ENV_PHP="      DB_HOST: ${ENV_NAME}_db
      DB_PORT: 3306
      DB_USERNAME: appuser
      DB_PASSWORD: apppassword
      DB_DATABASE: ${DB_NAME_VAR}"
  DB_DEPENDS="      - ${ENV_NAME}_db"
  DB_HEALTH="    healthcheck:
      test: [\"CMD\", \"mysqladmin\", \"ping\", \"-h\", \"localhost\", \"-u\", \"root\", \"-proot\"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s"
  DB_SERVICE="
  ${ENV_NAME}_db:
    image: $DB_IMAGE
    container_name: ${ENV_NAME}_db
    restart: unless-stopped
    ports:
      - \"${PORT_DB}:3306\"
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: ${DB_NAME_VAR}
      MYSQL_USER: appuser
      MYSQL_PASSWORD: apppassword
    volumes:
      - ${DB_VOLUME_NAME}:/var/lib/mysql
      - ./mysql/init:/docker-entrypoint-initdb.d:ro
$DB_HEALTH
    networks:
      - ${ENV_NAME}_net"
  DB_VOLUME_ENTRY="  ${DB_VOLUME_NAME}:
    name: ${DB_VOLUME_NAME}"
  DB_VOLUME_MOUNT="      - ${DB_VOLUME_NAME}:/var/lib/mysql"

elif [[ "$DB_ENGINE" == "postgres" ]]; then
  DB_NAME_VAR="${ENV_NAME//-/_}_db"
  DB_VOLUME_NAME="${ENV_NAME}_db_data"
  DB_ENV_PHP="      DB_HOST: ${ENV_NAME}_db
      DB_PORT: 5432
      DB_USERNAME: appuser
      DB_PASSWORD: apppassword
      DB_DATABASE: ${DB_NAME_VAR}"
  DB_DEPENDS="      - ${ENV_NAME}_db"
  DB_HEALTH="    healthcheck:
      test: [\"CMD-SHELL\", \"pg_isready -U appuser -d ${DB_NAME_VAR}\"]
      interval: 10s
      timeout: 5s
      retries: 5"
  DB_SERVICE="
  ${ENV_NAME}_db:
    image: $DB_IMAGE
    container_name: ${ENV_NAME}_db
    restart: unless-stopped
    ports:
      - \"${PORT_DB}:5432\"
    environment:
      POSTGRES_DB: ${DB_NAME_VAR}
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: apppassword
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ${DB_VOLUME_NAME}:/var/lib/postgresql/data
      - ./postgres/init:/docker-entrypoint-initdb.d:ro
$DB_HEALTH
    networks:
      - ${ENV_NAME}_net"
  DB_VOLUME_ENTRY="  ${DB_VOLUME_NAME}:
    name: ${DB_VOLUME_NAME}"
fi

# Bloco Redis
REDIS_SERVICE=""
REDIS_DEPENDS=""
REDIS_ENV_PHP=""
REDIS_VOLUME_NAME="${ENV_NAME}_redis_data"
REDIS_VOLUME_ENTRY=""

if $WITH_REDIS; then
  REDIS_ENV_PHP="      REDIS_HOST: ${ENV_NAME}_redis
      REDIS_PORT: 6379"
  REDIS_DEPENDS="      - ${ENV_NAME}_redis"
  REDIS_SERVICE="
  ${ENV_NAME}_redis:
    image: redis:7-alpine
    container_name: ${ENV_NAME}_redis
    restart: unless-stopped
    ports:
      - \"${PORT_REDIS}:6379\"
    volumes:
      - ${REDIS_VOLUME_NAME}:/data
    command: redis-server --appendonly yes
    networks:
      - ${ENV_NAME}_net"
  REDIS_VOLUME_ENTRY="  ${REDIS_VOLUME_NAME}:
    name: ${REDIS_VOLUME_NAME}"
fi

# Bloco depends_on para PHP
PHP_DEPENDS_BLOCK=""
ALL_DEPENDS="$DB_DEPENDS
$REDIS_DEPENDS"
TRIMMED_DEPENDS="$(echo "$ALL_DEPENDS" | sed '/^$/d')"
if [[ -n "$TRIMMED_DEPENDS" ]]; then
  PHP_DEPENDS_BLOCK="    depends_on:
$TRIMMED_DEPENDS"
fi

cat > "$ENV_DIR/docker-compose.yml" <<COMPOSE
# Ambiente: ${ENV_NAME}
# Gerado por new-env.sh em $(date '+%Y-%m-%d %H:%M')
# Gerenciar: ./manage.sh ${ENV_NAME} [up|down|build|logs|shell]

services:

  ${ENV_NAME}_nginx:
    image: nginx:alpine
    container_name: ${ENV_NAME}_nginx
    restart: unless-stopped
    ports:
      - "${PORT_HTTP}:80"
    volumes:
      - ./projects:/var/www
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
    depends_on:
      - ${ENV_NAME}_php
    networks:
      - ${ENV_NAME}_net

  ${ENV_NAME}_php:
    build:
      context: ./php
      dockerfile: Dockerfile
    image: ${ENV_NAME}_php:${PHP_VERSION}
    container_name: ${ENV_NAME}_php
    restart: unless-stopped
    working_dir: /var/www
    volumes:
      - ./projects:/var/www
      - ./php/local.ini:/usr/local/etc/php/conf.d/local.ini:ro
    environment:
      APP_ENV: local
${DB_ENV_PHP}
${REDIS_ENV_PHP}
      MAIL_HOST: ${ENV_NAME}_mailpit
      MAIL_PORT: 1025
${PHP_DEPENDS_BLOCK}
    networks:
      - ${ENV_NAME}_net
${DB_SERVICE}
${REDIS_SERVICE}

  ${ENV_NAME}_mailpit:
    image: axllent/mailpit:latest
    container_name: ${ENV_NAME}_mailpit
    restart: unless-stopped
    ports:
      - "${PORT_MAIL}:8025"
      - "$((PORT_MAIL + 1)):1025"
    networks:
      - ${ENV_NAME}_net

volumes:
${DB_VOLUME_ENTRY}
${REDIS_VOLUME_ENTRY}

networks:
  ${ENV_NAME}_net:
    name: ${ENV_NAME}_net
    driver: bridge
COMPOSE

# --- Script de projeto (Laravel/Symfony/genérico) ----------------------------
cat > "$ENV_DIR/new-project.sh" <<'PROJECTSCRIPT'
#!/usr/bin/env bash
set -euo pipefail
PROJECT="${1:-}"
[[ -z "$PROJECT" ]] && echo "Uso: $0 <nome-do-projeto>" && exit 1
ENV_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_NAME="$(basename "$ENV_DIR")"
COMPOSE="docker compose -f $ENV_DIR/docker-compose.yml"
PROJECTSCRIPT

# Adicionar bloco específico por framework
if [[ "$FRAMEWORK" == "laravel" ]]; then
  cat >> "$ENV_DIR/new-project.sh" <<'LARAVELBLOCK'
FRAMEWORK_VERSION="${2:-}"
PACKAGE="laravel/laravel${FRAMEWORK_VERSION:+:^${FRAMEWORK_VERSION}.0}"
$COMPOSE exec -u www ${ENV_NAME}_php composer create-project $PACKAGE "/var/www/$PROJECT" --prefer-dist --no-interaction
$COMPOSE exec ${ENV_NAME}_php bash -c "chown -R www:www /var/www/$PROJECT && chmod -R 775 /var/www/$PROJECT/storage /var/www/$PROJECT/bootstrap/cache 2>/dev/null || true"
$COMPOSE exec -u www ${ENV_NAME}_php bash -c "cd /var/www/$PROJECT && php artisan key:generate"
echo "Projeto Laravel criado: ./projects/$PROJECT"
LARAVELBLOCK

elif [[ "$FRAMEWORK" == "symfony" ]]; then
  cat >> "$ENV_DIR/new-project.sh" <<'SYMBLOCK'
$COMPOSE exec -u www ${ENV_NAME}_php composer create-project symfony/skeleton "/var/www/$PROJECT"
$COMPOSE exec ${ENV_NAME}_php bash -c "chown -R www:www /var/www/$PROJECT"
echo "Projeto Symfony criado: ./projects/$PROJECT"
SYMBLOCK

else
  cat >> "$ENV_DIR/new-project.sh" <<'GENBLOCK'
mkdir -p "$ENV_DIR/projects/$PROJECT/public"
echo "<?php phpinfo();" > "$ENV_DIR/projects/$PROJECT/public/index.php"
$COMPOSE exec ${ENV_NAME}_php bash -c "chown -R www:www /var/www/$PROJECT"
echo "Projeto genérico criado: ./projects/$PROJECT"
GENBLOCK
fi

chmod +x "$ENV_DIR/new-project.sh"

# --- Registrar portas no arquivo de registro ---------------------------------
{
  echo "${ENV_NAME}:http:${PORT_HTTP}"
  [[ "$DB_ENGINE" != "none" ]] && echo "${ENV_NAME}:db:${PORT_DB}"
  $WITH_REDIS && echo "${ENV_NAME}:redis:${PORT_REDIS}"
  echo "${ENV_NAME}:mail:${PORT_MAIL}"
} >> "$REGISTRY"

# --- Registrar metadados do ambiente -----------------------------------------
cat > "$ENV_DIR/.env-meta" <<META
ENV_NAME=${ENV_NAME}
PHP_VERSION=${PHP_VERSION}
DB_ENGINE=${DB_ENGINE}
DB_IMAGE=${DB_IMAGE}
WITH_REDIS=${WITH_REDIS}
WITH_NODE=${WITH_NODE}
FRAMEWORK=${FRAMEWORK}
PORT_HTTP=${PORT_HTTP}
PORT_DB=${PORT_DB:-}
PORT_REDIS=${PORT_REDIS:-}
PORT_MAIL=${PORT_MAIL}
CREATED_AT="$(date '+%Y-%m-%d %H:%M')"
META

# =============================================================================
echo ""
success "Ambiente '${ENV_NAME}' criado em $ENV_DIR"
echo ""
echo -e "  ${BOLD}Próximos passos:${RESET}"
echo ""
echo -e "  ${CYAN}1.${RESET} Subir o ambiente:"
echo -e "     ${BOLD}./manage.sh ${ENV_NAME} up${RESET}"
echo ""
echo -e "  ${CYAN}2.${RESET} Criar um projeto:"
echo -e "     ${BOLD}./manage.sh ${ENV_NAME} new-project meu-app${RESET}"
echo ""
echo -e "  ${CYAN}3.${RESET} Ver todos os ambientes:"
echo -e "     ${BOLD}./manage.sh list${RESET}"
echo ""
