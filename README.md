# Docker multi-ambiente — geração dinâmica

Crie quantos ambientes PHP isolados quiser com um único script interativo. Cada ambiente tem seu próprio `docker-compose.yml`, rede, volumes e containers — sem editar nada à mão.

---

## Estrutura

```
docker-envs/
├── new-env.sh          ← cria novos ambientes (interativo)
├── manage.sh           ← gerencia todos os ambientes
└── envs/
    ├── .registry       ← registro de portas em uso (gerado automaticamente)
    │
    ├── cliente-x/      ← cada ambiente é uma pasta isolada
    │   ├── docker-compose.yml   (gerado)
    │   ├── .env-meta            (metadados do ambiente)
    │   ├── new-project.sh       (gerado — específico para o framework)
    │   ├── php/
    │   │   ├── Dockerfile       (gerado)
    │   │   └── local.ini        (gerado)
    │   ├── nginx/conf.d/        (vhosts criados automaticamente)
    │   └── projects/            (código dos projetos)
    │
    └── equipe-backend/
        └── ...
```

---

## Criar um novo ambiente

```bash
chmod +x new-env.sh manage.sh
./new-env.sh
```

O script pergunta:

| Passo | Opções |
|---|---|
| Nome | Qualquer identificador (ex: `cliente-x`, `equipe-api`) |
| PHP | 8.4, 8.3, 8.2, 8.1, 8.0, 7.4, ou outra |
| Banco | MySQL 8/5.7, PostgreSQL 16/15/13, MariaDB 11, ou nenhum |
| Redis | Sim / Não |
| Framework | Laravel, Symfony, ou genérico |
| Node.js | 22 LTS, 20 LTS, ou não incluir |
| Portas | Detecta conflitos e sugere portas livres automaticamente |

Ao final exibe um resumo e pede confirmação antes de gerar qualquer arquivo.

---

## Gerenciar ambientes

### Ver todos

```bash
./manage.sh list
```

Saída:
```
  Ambientes disponíveis
  ──────────────────────────────────────────────────────────────────
  Nome                 PHP      Banco            Framework  Portas
  ──────────────────────────────────────────────────────────────────
  ● cliente-x          8.4      mysql:3307       laravel    :8080 / mail:8025
  ○ equipe-backend     8.2      postgres:5433    laravel    :8081 / mail:8026
  ○ sistema-legado     7.4      mysql:3308       generic    :8082 / mail:8027

  ● rodando  ○ parado
```

### Subir / derrubar

```bash
# Um ambiente
./manage.sh cliente-x up
./manage.sh cliente-x down

# Todos de uma vez
./manage.sh all up
./manage.sh all down
```

### Criar projetos dentro de um ambiente

```bash
./manage.sh cliente-x new-project meu-app
./manage.sh cliente-x new-project loja 11        # Laravel 11 especificamente
```

O comando cria o projeto, gera o vhost Nginx e recarrega o Nginx automaticamente.  
Adicione ao `/etc/hosts`: `127.0.0.1  meu-app.localhost`  
Acesse em: `http://meu-app.localhost:<porta-do-ambiente>`

### Outros comandos

```bash
# Shell no container PHP
./manage.sh cliente-x shell

# Artisan
./manage.sh cliente-x artisan meu-app migrate
./manage.sh cliente-x artisan meu-app "make:model Post -m"

# Composer
./manage.sh cliente-x composer meu-app "require spatie/laravel-permission"

# CLI do banco de dados
./manage.sh cliente-x db

# Logs em tempo real
./manage.sh cliente-x logs             # todos os serviços
./manage.sh cliente-x logs php         # só o PHP
./manage.sh cliente-x logs nginx       # só o Nginx

# Rebuildar imagem PHP (após mudar Dockerfile)
./manage.sh cliente-x build

# Status dos containers
./manage.sh cliente-x status

# Destruir ambiente e apagar volumes
./manage.sh cliente-x destroy
```

---

## Isolamento garantido

Cada ambiente tem:

- **Rede própria** (`cliente-x_net`) — containers de ambientes diferentes não se comunicam
- **Volumes com nome único** (`cliente-x_db_data`, `cliente-x_redis_data`)
- **Containers com nome único** (`cliente-x_php`, `cliente-x_nginx`, ...)
- **Portas únicas no host** — o script detecta automaticamente o que está em uso
- **`docker-compose.yml` próprio** — `docker compose down` em um não afeta os outros

---

## Personalizar após a criação

Os arquivos gerados são seus — edite livremente:

```
envs/cliente-x/php/Dockerfile    ← adicionar extensões
envs/cliente-x/php/local.ini     ← ajustar limites PHP
envs/cliente-x/nginx/conf.d/     ← adicionar vhosts manualmente
envs/cliente-x/docker-compose.yml ← ajustar variáveis, recursos, etc.
```

Após editar o Dockerfile:
```bash
./manage.sh cliente-x build
./manage.sh cliente-x restart
```

---

## Dica: dnsmasq para resolver `*.localhost` automaticamente

Sem precisar editar `/etc/hosts` para cada projeto:

**macOS:**
```bash
brew install dnsmasq
echo "address=/.localhost/127.0.0.1" >> /opt/homebrew/etc/dnsmasq.conf
sudo brew services start dnsmasq
sudo mkdir -p /etc/resolver && echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/localhost
```

**Linux:**
```bash
sudo apt install dnsmasq
echo "address=/.localhost/127.0.0.1" | sudo tee /etc/dnsmasq.d/localhost.conf
sudo systemctl restart dnsmasq
```

---

## Comandos Manage.sh

  manage.sh — Gerencia todos os ambientes Docker

    ./manage.sh list                         Lista todos os ambientes
    ./manage.sh <env> up                     Sobe o ambiente
    ./manage.sh <env> down                   Derruba o ambiente
    ./manage.sh <env> build                  Rebuilda as imagens
    ./manage.sh <env> restart                Reinicia todos os containers
    ./manage.sh <env> logs [serviço]         Exibe logs (follow)
    ./manage.sh <env> shell                  Shell no container PHP
    ./manage.sh <env> new-project <nome>     Cria novo projeto
    ./manage.sh <env> artisan <cmd>          Roda artisan em todos os projetos
    ./manage.sh <env> composer <cmd>         Roda composer (na raiz)
    ./manage.sh <env> db                     CLI do banco de dados
    ./manage.sh <env> status                 Status dos containers
    ./manage.sh <env> destroy                Apaga o ambiente e volumes
    ./manage.sh all up                       Sobe TODOS os ambientes
    ./manage.sh all down                     Derruba TODOS os ambientes
    ./manage.sh all status                   Status de TODOS