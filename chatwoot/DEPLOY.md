# Chatwoot Deploy Guide — Turbo Track

Stack: chatwoot-web, chatwoot-worker, redis, postgres via Docker Compose.

## Pré-requisitos na VPS

- Ubuntu 22.04+
- Docker Engine 24+ + Docker Compose plugin
- Porta 3000 aberta no firewall

```bash
# Instalar Docker (se necessário)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

## Deploy

```bash
# 1. Copiar arquivos para a VPS
scp -r chatwoot/ user@VPS_IP:~/chatwoot/
ssh user@VPS_IP "cd ~/chatwoot"

# 2. Configurar variáveis de ambiente
cp .env.chatwoot.example .env.chatwoot
# Editar os valores (no mínimo obrigatórios):
#   SECRET_KEY_BASE  → openssl rand -hex 64
#   POSTGRES_PASSWORD → senha forte
#   REDIS_PASSWORD   → senha forte
#   FRONTEND_URL     → http://<VPS_IP>:3000
#   SUPER_ADMIN_EMAIL → seu email de admin
nano .env.chatwoot

# 3. Subir stack
docker compose up -d

# 4. Validar saúde dos serviços
docker compose ps
docker compose logs chatwoot-web --tail 50

# 5. Validar HTTP
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/auth/sign_in
# Esperado: 200
```

## Criação de Account (Tenant)

```bash
# Criar super admin via Rails console (apenas 1x no setup inicial)
docker compose exec chatwoot-web bundle exec rails console
# No console Rails:
SuperAdmin.create!(email: 'admin@seudominio.com', password: 'senha-forte')

# Depois, criar Account via script:
./create-chatwoot-account.sh "Nome do Tenant" admin@seudominio.com senha-forte
```

## Variáveis mínimas obrigatórias

| Variável | Descrição |
|---|---|
| `SECRET_KEY_BASE` | `openssl rand -hex 64` |
| `POSTGRES_PASSWORD` | senha do banco |
| `REDIS_PASSWORD` | senha do Redis |
| `FRONTEND_URL` | URL pública do Chatwoot |
| `SUPER_ADMIN_EMAIL` | email do super admin inicial |
| `DATABASE_URL` | deve coincidir com `POSTGRES_*` |
| `REDIS_URL` | deve incluir `REDIS_PASSWORD` |

## Próximos passos (Semana 2)

Após validação, configurar Evolution API apontando para o Inbox criado pelo script:
- Webhook URL: `http://<VPS_IP>:3000/api/v1/accounts/<ACCOUNT_ID>/...`
- Ver [EMP-42](/EMP/issues/EMP-42#document-plan) seção 3.4 para detalhes da integração
