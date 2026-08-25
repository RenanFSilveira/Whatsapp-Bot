-- Migration 001: WhatsApp routing tables
-- Run once via Supabase SQL Editor: https://supabase.com/dashboard/project/wzjeqmoybsriqqwoxdgq/sql
--
-- Design: keeps existing tables (mensagens, leads, tenants) 100% untouched.
-- Only new tables added. Supabase free tier protected — no message bodies stored here.

-- Maps Evolution API instance names to tenants + Chatwoot inbox
CREATE TABLE IF NOT EXISTS whatsapp_instances (
    id                  UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id           UUID        REFERENCES tenants(id) ON DELETE CASCADE,
    instance_name       TEXT        UNIQUE NOT NULL,
    chatwoot_inbox_id   INTEGER     NOT NULL,
    forward_url         TEXT,       -- optional n8n or other webhook to forward events to
    active              BOOLEAN     DEFAULT TRUE,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- Lightweight routing log — full messages live in Chatwoot (zero message body here)
CREATE TABLE IF NOT EXISTS whatsapp_mensagens (
    id                          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id                   UUID        REFERENCES tenants(id),
    instance_name               TEXT        NOT NULL,
    remote_jid                  TEXT        NOT NULL,
    message_id                  TEXT        UNIQUE NOT NULL,
    direction                   TEXT        NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    message_type                TEXT,
    chatwoot_conversation_id    INTEGER,
    created_at                  TIMESTAMPTZ DEFAULT NOW()
);

-- Index for querying by tenant + phone
CREATE INDEX IF NOT EXISTS idx_wa_mensagens_tenant ON whatsapp_mensagens(tenant_id, remote_jid);

-- Seed: map Renan_Performance instance to innova-odonto tenant (used for initial testing)
-- Chatwoot inbox_id=1 was created via API (WhatsApp - Renan_Performance)
INSERT INTO whatsapp_instances (tenant_id, instance_name, chatwoot_inbox_id, forward_url)
SELECT id, 'Renan_Performance', 1, 'https://n8n.respondipravoce.com.br/webhook/whatsapp-grupos'
FROM tenants WHERE slug = 'innova-odonto'
ON CONFLICT (instance_name) DO NOTHING;
