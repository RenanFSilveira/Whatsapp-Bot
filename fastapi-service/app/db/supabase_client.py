from functools import lru_cache
from typing import Any

from supabase import Client, create_client

from app.core.config import settings


@lru_cache(maxsize=1)
def get_supabase() -> Client:
    if not settings.supabase_url or not settings.supabase_service_key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_KEY must be set")
    return create_client(settings.supabase_url, settings.supabase_service_key)


def get_mensagens(tenant_id: str, limit: int = 100) -> list[dict[str, Any]]:
    """Fetch messages for a tenant, scoped strictly to that tenant_id."""
    client = get_supabase()
    response = (
        client.table("mensagens")
        .select("*")
        .eq("tenant_id", tenant_id)
        .limit(limit)
        .execute()
    )
    return response.data or []


def get_whatsapp_instance(instance_name: str) -> dict[str, Any] | None:
    """Resolve tenant_id and chatwoot_inbox_id from instance name."""
    client = get_supabase()
    response = (
        client.table("whatsapp_instances")
        .select("*")
        .eq("instance_name", instance_name)
        .eq("active", True)
        .limit(1)
        .execute()
    )
    rows = response.data or []
    return rows[0] if rows else None


def insert_whatsapp_event(
    *,
    tenant_id: str,
    instance_name: str,
    remote_jid: str,
    message_id: str,
    direction: str,
    message_type: str,
    chatwoot_conversation_id: int | None,
) -> None:
    """Insert a lightweight routing record. Full message lives in Chatwoot."""
    client = get_supabase()
    client.table("whatsapp_mensagens").upsert(
        {
            "tenant_id": tenant_id,
            "instance_name": instance_name,
            "remote_jid": remote_jid,
            "message_id": message_id,
            "direction": direction,
            "message_type": message_type,
            "chatwoot_conversation_id": chatwoot_conversation_id,
        },
        on_conflict="message_id",
        ignore_duplicates=True,
    ).execute()
