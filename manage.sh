#!/usr/bin/env bash
# =============================================================================
#  manage.sh — Gerencia todos os ambientes Docker
#
#  Uso:
#    ./manage.sh list                         Lista todos os ambientes
#    ./manage.sh <env> up                     Sobe o ambiente
#    ./manage.sh <env> down                   Derruba o ambiente
#    ./manage.sh <env> build                  Rebuilda as imagens
#    ./manage.sh <env> restart                Reinicia todos os containers
#    ./manage.sh <env> logs [serviço]         Exibe logs (follow)
#    ./manage.sh <env> shell                  Shell no container PHP
#    ./manage.sh <env> new-project <nome>     Cria novo projeto
#    ./manage.sh <env> artisan <cmd>          Roda artisan em todos os projetos
#    ./manage.sh <env> composer <cmd>         Roda composer (na raiz)
#    ./manage.sh <env> db                     CLI do banco de dados
#    ./manage.sh <env> status                 Status dos containers
#    ./manage.sh <env> destroy                Apaga o ambiente e volumes
#    ./manage.sh all up                       Sobe TODOS os ambientes
#    ./manage.sh all down                     Derruba TODOS os ambientes
#    ./manage.sh all status                   Status de TODOS
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENVS_DIR="$ROOT/envs"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

info()    { echo -e "${CYAN}  →${RESET} $*"; }
success() { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}  !${RESET} $*"; }
error()   { echo -e "${RED}  ✗${RESET} $*" >&2; exit 1; }

# --- helpers -----------------------------------------------------------------
env_exists() { [[ -d "$ENVS_DIR/$1" && -f "$ENVS_DIR/$1/docker-compose.yml" ]]; }
load_meta()  { [[ -f "$ENVS_DIR/$1/.env-meta" ]] && source "$ENVS_DIR/$1/.env-meta"; }

compose() {
  local env="$1"; shift
  docker compose -f "$ENVS_DIR/$env/docker-compose.yml" --project-directory "$ENVS_DIR/$env" "$@"
}

require_env() {
  local env="$1"
  env_exists "$env" || error "Ambiente '$env' não encontrado. Use './manage.sh list' para ver os disponíveis."
}

# =============================================================================
#  COMANDOS
# =============================================================================
CMD_TARGET="${1:-}"
CMD_ACTION="${2:-help}"

[[ -z "$CMD_TARGET" ]] && CMD_ACTION="help"

# --- list --------------------------------------------------------------------
if [[ "$CMD_TARGET" == "list" || "$CMD_ACTION" == "help" && -z "$CMD_TARGET" ]]; then
  echo ""
  echo -e "${BOLD}  Ambientes disponíveis${RESET}"
  echo -e "  ${DIM}────────────────────────────────────────────────────────────────${RESET}"
  printf "  ${BOLD}%-20s %-8s %-16s %-10s %-18s${RESET}\n" "Nome" "PHP" "Banco" "Framework" "Portas"
  echo -e "  ${DIM}────────────────────────────────────────────────────────────────${RESET}"

  found=0
  for env_dir in "$ENVS_DIR"/*/; do
    [[ -f "$env_dir/.env-meta" ]] || continue
    source "$env_dir/.env-meta"
    found=1

    # Checar se está rodando
    running=$(docker compose -f "$env_dir/docker-compose.yml" --project-directory "$env_dir" \
              ps --status running -q 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$running" -gt 0 ]]; then
      status="${GREEN}●${RESET}"
    else
      status="${DIM}○${RESET}"
    fi

    DB_DISPLAY="${DB_ENGINE:-none}:${PORT_DB:-—}"
    PORTS_DISPLAY=":${PORT_HTTP} / mail:${PORT_MAIL}"
    printf "  %b %-19s %-8s %-16s %-10s %-18s\n" \
      "$status" "$ENV_NAME" "$PHP_VERSION" "$DB_DISPLAY" "$FRAMEWORK" "$PORTS_DISPLAY"
  done

  if [[ $found -eq 0 ]]; then
    echo -e "  ${DIM}Nenhum ambiente criado. Use ./new-env.sh para criar o primeiro.${RESET}"
  fi
  echo ""
  echo -e "  ${DIM}● rodando  ○ parado${RESET}"
  echo ""
  exit 0
fi

# --- all ---------------------------------------------------------------------
if [[ "$CMD_TARGET" == "all" ]]; then
  ACTION="$CMD_ACTION"
  for env_dir in "$ENVS_DIR"/*/; do
    [[ -f "$env_dir/.env-meta" ]] || continue
    ENV_NAME="$(basename "$env_dir")"
    info "[$ENV_NAME] $ACTION..."
    case "$ACTION" in
      up)     compose "$ENV_NAME" up -d ;;
      down)   compose "$ENV_NAME" down ;;
      status) compose "$ENV_NAME" ps ;;
      build)  compose "$ENV_NAME" build ;;
      *)      error "Ação '$ACTION' não suportada para 'all'" ;;
    esac
  done
  exit 0
fi

# --- comandos por ambiente ---------------------------------------------------
ENV="$CMD_TARGET"
ACTION="${CMD_ACTION:-}"
require_env "$ENV"
load_meta "$ENV"

case "$ACTION" in

  up)
    info "Subindo ambiente '$ENV'..."
    compose "$ENV" up -d --build
    echo ""
    success "Ambiente '$ENV' rodando!"
    echo -e "  HTTP:    ${CYAN}http://localhost:${PORT_HTTP}${RESET}"
    [[ -n "${PORT_DB:-}" ]] && echo -e "  Banco:   localhost:${PORT_DB}"
    echo -e "  Mailpit: ${CYAN}http://localhost:${PORT_MAIL}${RESET}"
    echo ""
    ;;

  down)
    info "Derrubando ambiente '$ENV'..."
    compose "$ENV" down
    success "Ambiente '$ENV' parado. Volumes preservados."
    ;;

  restart)
    compose "$ENV" restart
    success "Ambiente '$ENV' reiniciado."
    ;;

  build)
    info "Rebuilding imagem PHP de '$ENV'..."
    compose "$ENV" build "${ENV}_php"
    success "Build concluído."
    ;;

  logs)
    SERVICE="${3:-}"
    if [[ -n "$SERVICE" ]]; then
      compose "$ENV" logs -f "${ENV}_${SERVICE}"
    else
      compose "$ENV" logs -f
    fi
    ;;

  shell)
    info "Abrindo shell no container PHP de '$ENV'..."
    compose "$ENV" exec -u www "${ENV}_php" bash
    ;;

  new-project)
    PROJECT="${3:-}"
    [[ -z "$PROJECT" ]] && error "Informe o nome do projeto: ./manage.sh $ENV new-project <nome>"
    bash "$ENVS_DIR/$ENV/new-project.sh" "$PROJECT" "${4:-}"

    # Criar vhost Nginx para o projeto
    cat > "$ENVS_DIR/$ENV/nginx/conf.d/${PROJECT}.conf" <<NGINX
server {
    listen 80;
    server_name ${PROJECT}.localhost;
    root /var/www/${PROJECT}/public;
    index index.php index.html;
    charset utf-8;
    client_max_body_size 128M;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg|woff|woff2)$ {
        expires 30d; try_files \$uri =404;
    }
    location ~ \.php$ {
        fastcgi_pass ${ENV}_php:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }
    location ~ /\.(?!well-known).* { deny all; }
}
NGINX

    compose "$ENV" exec "${ENV}_nginx" nginx -s reload 2>/dev/null || true
    echo ""
    success "Projeto '$PROJECT' criado!"
    echo -e "  URL: ${CYAN}http://${PROJECT}.localhost:${PORT_HTTP}${RESET}"
    echo ""
    echo "  Adicione ao /etc/hosts:"
    echo "  127.0.0.1  ${PROJECT}.localhost"
    ;;

  artisan)
    shift 2
    PROJECT="${1:-}"
    shift || true
    [[ -z "$PROJECT" ]] && error "Uso: ./manage.sh $ENV artisan <projeto> <comando>"
    compose "$ENV" exec -u www "${ENV}_php" bash -c "cd /var/www/$PROJECT && php artisan $*"
    ;;

  composer)
    shift 2
    PROJECT="${1:-}"
    shift || true
    [[ -z "$PROJECT" ]] && error "Uso: ./manage.sh $ENV composer <projeto> <comando>"
    compose "$ENV" exec -u www "${ENV}_php" bash -c "cd /var/www/$PROJECT && composer $*"
    ;;

  db)
    if [[ "${DB_ENGINE:-none}" == "mysql" ]]; then
      compose "$ENV" exec "${ENV}_db" mysql -u appuser -papppassword
    elif [[ "${DB_ENGINE:-none}" == "postgres" ]]; then
      compose "$ENV" exec "${ENV}_db" psql -U appuser -d "${ENV_NAME//-/_}_db"
    else
      error "Este ambiente não tem banco de dados configurado."
    fi
    ;;

  status)
    compose "$ENV" ps
    ;;

  destroy)
    echo -e "${RED}  ATENÇÃO: Isso apagará o ambiente '$ENV' e todos os seus volumes de dados.${RESET}"
    read -rp "  Confirmar digitando o nome do ambiente: " CONFIRM_NAME
    [[ "$CONFIRM_NAME" != "$ENV" ]] && echo "Cancelado." && exit 0
    compose "$ENV" down -v
    rm -rf "$ENVS_DIR/$ENV"
    grep -v "^${ENV}:" "$ENVS_DIR/.registry" > /tmp/.reg_tmp && mv /tmp/.reg_tmp "$ENVS_DIR/.registry"
    success "Ambiente '$ENV' destruído."
    ;;

  *)
    echo ""
    echo -e "${BOLD}  Uso: ./manage.sh <ambiente> <ação>${RESET}"
    echo ""
    echo "  Ações disponíveis:"
    echo "    up                    Sobe o ambiente (com build automático)"
    echo "    down                  Derruba o ambiente"
    echo "    restart               Reinicia os containers"
    echo "    build                 Rebuilda a imagem PHP"
    echo "    logs [serviço]        Logs em tempo real (php, nginx, db, redis)"
    echo "    shell                 Shell no container PHP"
    echo "    new-project <nome>    Cria novo projeto"
    echo "    artisan <proj> <cmd>  php artisan no projeto"
    echo "    composer <proj> <cmd> composer no projeto"
    echo "    db                    CLI do banco de dados"
    echo "    status                Status dos containers"
    echo "    destroy               Remove ambiente e volumes"
    echo ""
    echo -e "  Use ${CYAN}./manage.sh list${RESET} para ver todos os ambientes."
    echo ""
    ;;
esac
