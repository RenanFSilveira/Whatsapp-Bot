# Status Atual do TurboTrack — Relatório Completo

**Data:** 2026-08-26 | **Último sync EMP-65:** 2026-08-26 | **Autor:** Analista de Projeto | **Issue:** EMP-56

---

## 1. O que já temos ✅

### App Next.js — turbo-track (repo externo)

✅ **Fases 0 e 1 completas** — telas MVP no ar:
- `/dashboard` — visão geral de leads e KPIs
- `/sla` — painel de cumprimento de SLA de resposta (horário comercial)
- `/leads` — lista + board kanban (visualização estática)
- `/leads/[id]` — detalhe do lead com histórico de mensagens
- `/configuracoes` — configurações do tenant

✅ **Auth completa (NextAuth v5 + Google OAuth)**
- Allowlist relacional via tabela `memberships` (migration 0006)
- Gate server-side em toda rota via `resolveTenantContext` em `src/lib/access.ts`
- Rotas com `?tenant=` fora do escopo retornam 404
- Escrita protegida por `requireAgencyAdmin`
- Seed: `renan.fortunato@turbopartners.com.br` = agency_admin

✅ **1 tenant carregado: Innova Odonto**
- ID: `7504b091-aacc-4cd2-ab09-b2c5f26882dd`
- 497 leads + 8.487 mensagens carregados via ETL sombra + reconciliação

### Supabase (project ref: `wzjeqmoybsriqqwoxdgq`)

✅ **Schema completo — migrations 0001-0006:**

| Migration | Tabela/Objeto |
|---|---|
| 0001 | `tenants` |
| 0002 | `leads`, `mensagens` |
| 0003 | `eventos_capi` |
| 0004 | `kpis_sla`, `sync_state` |
| 0005 | Views de dashboard |
| 0006 | `memberships` + seed agency_admin |

✅ **RLS ativo** em todas as tabelas com isolamento por tenant

### Repo Integrador (este repo — projeto Paperclip)

✅ **FastAPI scaffold (EMP-51, done):**
- Poetry + estrutura de pacotes (`app/core`, `app/api`, `app/db`, `app/services`, `app/middleware`)
- JWT auth com tenant scoping (`CurrentTenant` middleware)
- `GET /health` e `GET /mensagens` (tenant-scoped)
- Dockerfile + `docker-compose.yml` para deploy

✅ **Webhook bidirecional WhatsApp ↔ Chatwoot (commits recentes):**
- `POST /webhook/evolution/{instance}` — recebe MESSAGES_UPSERT da Evolution API
- `POST /webhook/chatwoot` — recebe replies do agente no Chatwoot e envia via WhatsApp
- Guard de idempotência por `message_id` (TTL 5min, in-memory)
- Forward para n8n via `WEBHOOK_FORWARD_URL` — **todos** os eventos (grupos, outbound, individuais) encaminhados **antes** dos filtros Chatwoot (commit `1c2d992`)
- Skip de mensagens `fromMe` e grupos (`@g.us`) apenas para o processamento Chatwoot (filtros exclusivos do Chatwoot; n8n já recebeu o evento acima)
- Serviços: `chatwoot.py` (find_or_create_contact/conversation, post_message) e `evolution.py` (send_text_message)

✅ **Chatwoot Docker Compose (EMP-52 — pronto, aguardando VPS):**
- `chatwoot/docker-compose.yml` com PostgreSQL 15 + Redis 7 + Chatwoot v3.12.0 (web + worker)
- Memory limits: ~1.5GB total (postgres 256m, redis 256m, web 512m, worker 512m)
- Labels Traefik configurados para `chat.respondipravoce.com.br` + SSL Let's Encrypt
- `.env.chatwoot.example`, `create-chatwoot-account.sh`, `DEPLOY.md` — tudo pronto
- **Status: PRONTO para deploy, bloqueado por falta de VPS**

✅ **ADRs Semana 1 (EMP-53 + EMP-54, done):**
- ADR-001, ADR-002 e Gap Analysis produzidos e revisados

✅ **ETL Scripts (workspace-turbo, commitados):**
- `scripts/supabase/client.py`, `etl_sheets.py`, `reconcile.py`
- Pipeline legado (Apps Script → n8n → Supabase) **em operação contínua**

✅ **Time contratado:**
- Analista de Projeto, Dev Frontend ×2, Dev Backend Python, Especialista Integrações
- **Status: todos idle, aguardando VPS**
- CTO: paused desde jun/2026

---

## 2. O que falta

### 🔴 Semana 2 — Deploy Chatwoot + Evolution API na VPS
Tudo pronto no repo, VPS não disponível (EMP-52 bloqueado). Sem isso toda a Semana 2 em diante está paralisada.

### 🟡 Semana 3 — Webhooks Chatwoot → FastAPI
Pipeline de mensagens ao vivo (depende da Semana 2). Adapter pattern + pipeline paralelo com legado.

### 🟡 Semanas 4-5 — Chat ao vivo
WebSocket/ActionCable consumindo Chatwoot API (Dev Frontend). Painel em tempo real no `/leads/[id]`.

### 🟡 Semanas 5-6 — Kanban arrastável
@dnd-kit no `/leads` (Dev Frontend). Drag-and-drop entre colunas.

### 🟡 Semanas 3-4 — BERTimbau Sentimento
Dataset de conversas WhatsApp pt-BR, fine-tuning, serving (Dev Backend Python).

### 🟡 Semanas 5-6 — RAG por Tenant
pgvector + embeddings + endpoint `/copilot`. Recuperação semântica por tenant.

### 🟡 Semanas 6-7 — Copilot Sidebar
Painel lateral no chat com sugestões de resposta (Dev Frontend + Dev Backend).

### 🟡 Semanas 7-8 — Lead Scoring + Auditoria
XGBoost/MLP, feature engineering com dados históricos Innova (Dev Backend Python).

### 🟡 Semanas 8-10 — Dashboard de Sentimento + Virada CAPI
Gráficos Recharts em tempo real + reconectar motor CTWA/CAPI ao novo fluxo (Fase 3).

### 🟡 Semanas 11-12 — Onboarding Automatizado
FastAPI cria Account + Inbox no Chatwoot automaticamente (substitui script manual).

### 🟡 Backlog
- Tela `/admin/acessos` — CRUD de memberships pela UI
- Fase 3 — Pricing R$200/mês — provisionador, ROAS

---

## 3. Pré-requisitos para seguir

### #1 🔴 VPS com IP público + SSH (bloqueador crítico)
Todo o código está pronto. Sem VPS, o time inteiro permanece idle.
**Ação: quem provisiona a VPS? Orçamento aprovado?**

### #2 🟡 Número de WhatsApp de desenvolvimento (não produção)
Para testar integração Evolution API sem afetar clientes reais.

### #3 🟡 Decisão sobre segundo tenant
- Opção A: tenant fictício com dados sintéticos (rápido)
- Opção B: destravar Nina (em churn + 4 pendências — maior risco)

### #4 🟡 Budget para embeddings
- OpenAI `text-embedding-3-small` (~$0,02/1M tokens, sem GPU) vs `sentence-transformers` local (gratuito, requer GPU)

### #5 🟡 Google Colab / GPU para fine-tuning BERTimbau
Colab Pro+ (~$50/mês) suficiente. Alternativa: RunPod ou Modal (pay-per-use).

### #6 🟡 Credenciais Meta/CAPI para o novo fluxo
Só na Fase 3, mas aprovação Meta demora — iniciar processo agora.

---

### Invariante crítico ✅

**Pipeline legado (Apps Script → n8n → Supabase) deve continuar rodando em PARALELO até validação completa do novo fluxo.** É a única fonte de dados em produção da Innova hoje.

---

## Resumo Executivo

Situação técnica boa: Next.js no ar, Supabase configurado, FastAPI com webhook bidirecional, Chatwoot pronto para deploy. **O único bloqueador real é a VPS.** Assim que provisionada, o Especialista Integrações inicia a Semana 2 imediatamente.
