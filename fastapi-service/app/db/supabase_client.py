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
