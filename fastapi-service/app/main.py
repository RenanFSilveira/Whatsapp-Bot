from fastapi import FastAPI

from app.middleware.auth import CurrentTenant
from app.db.supabase_client import get_mensagens
from app.api.webhook import router as webhook_router

app = FastAPI(
    title="Turbo Track AI",
    version="0.1.0",
    description="AI backend for Turbo Track WhatsApp Sales Intelligence",
)

app.include_router(webhook_router)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "turbo-track-ai"}


@app.get("/mensagens")
def list_mensagens(tenant: CurrentTenant, limit: int = 100) -> dict:
    """Return messages for the authenticated tenant only."""
    data = get_mensagens(tenant_id=tenant.tenant_id, limit=limit)
    return {"tenant_id": tenant.tenant_id, "count": len(data), "data": data}
