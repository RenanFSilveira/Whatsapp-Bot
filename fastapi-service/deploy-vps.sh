#!/bin/bash
# TurboTrack FastAPI — one-shot deploy script
# Run on VPS via SSH: bash deploy-vps.sh
# Creates all files and starts the container via Coolify-compatible docker-compose

set -e

DEPLOY_DIR="/root/turbotrack-api"
mkdir -p "$DEPLOY_DIR/app/api" "$DEPLOY_DIR/app/core" "$DEPLOY_DIR/app/db" "$DEPLOY_DIR/app/middleware" "$DEPLOY_DIR/app/services"

# ── pyproject.toml ───────────────────────────────────────────────────────────
cat > "$DEPLOY_DIR/pyproject.toml" <<'PYPROJECT'
[tool.poetry]
name = "turbo-track-ai"
version = "0.1.0"
description = "Turbo Track AI Backend Service"
authors = ["Turbo Partners <dev@turbopartners.com.br>"]
packages = [{include = "app"}]

[tool.poetry.dependencies]
python = "^3.11"
fastapi = "^0.111.0"
uvicorn = {extras = ["standard"], version = "^0.30.0"}
pydantic = "^2.7.0"
pydantic-settings = "^2.3.0"
python-jose = {extras = ["cryptography"], version = "^3.3.0"}
supabase = "^2.5.0"
httpx = "^0.27.0"

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"
PYPROJECT

# ── Dockerfile ───────────────────────────────────────────────────────────────
cat > "$DEPLOY_DIR/Dockerfile" <<'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
RUN pip install poetry==1.8.3 && poetry config virtualenvs.create false
COPY pyproject.toml ./
RUN poetry install --no-interaction --no-ansi --only main --no-root
COPY app ./app
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
DOCKERFILE

# ── docker-compose.yml ───────────────────────────────────────────────────────
cat > "$DEPLOY_DIR/docker-compose.yml" <<'COMPOSE'
version: "3.8"
services:
  turbotrack-api:
    build: .
    restart: unless-stopped
    env_file:
      - .env
    labels:
      - traefik.enable=true
      - traefik.docker.network=coolify
      - traefik.http.middlewares.api-redirect-https.redirectscheme.scheme=https
      - traefik.http.routers.http-turbotrack.entryPoints=http
      - traefik.http.routers.http-turbotrack.middlewares=api-redirect-https
      - "traefik.http.routers.http-turbotrack.rule=Host(`api.respondipravoce.com.br`)"
      - traefik.http.routers.https-turbotrack.entryPoints=https
      - "traefik.http.routers.https-turbotrack.rule=Host(`api.respondipravoce.com.br`)"
      - traefik.http.routers.https-turbotrack.tls=true
      - traefik.http.routers.https-turbotrack.tls.certresolver=letsencrypt
      - traefik.http.services.turbotrack-svc.loadbalancer.server.port=8000
    networks:
      - coolify
networks:
  coolify:
    external: true
COMPOSE

# ── .env ─────────────────────────────────────────────────────────────────────
cat > "$DEPLOY_DIR/.env" <<'ENVFILE'
SUPABASE_URL=https://wzjeqmoybsriqqwoxdgq.supabase.co
SUPABASE_SERVICE_KEY=sb_secret_rwTxG5hLsOnyVFDgUZI8Nw_7FngK_gq
JWT_SECRET=change-me-in-production
JWT_ALGORITHM=HS256
JWT_AUDIENCE=turbo-track
CHATWOOT_URL=https://chat.respondipravoce.com.br
CHATWOOT_API_TOKEN=KxEE6c49EaW82ng3SngnVruY
CHATWOOT_ACCOUNT_ID=1
EVOLUTION_API_URL=https://evo.respondipravoce.com.br
EVOLUTION_API_KEY=CD642396E2FE-482C-A642-1BABE4D84D0E
WEBHOOK_FORWARD_URL=https://n8n.respondipravoce.com.br/webhook/whatsapp-grupos
ENVFILE

# ── app/__init__.py ───────────────────────────────────────────────────────────
touch "$DEPLOY_DIR/app/__init__.py"
touch "$DEPLOY_DIR/app/api/__init__.py"
touch "$DEPLOY_DIR/app/core/__init__.py"
touch "$DEPLOY_DIR/app/db/__init__.py"
touch "$DEPLOY_DIR/app/middleware/__init__.py"
touch "$DEPLOY_DIR/app/services/__init__.py"

# ── app/core/config.py ───────────────────────────────────────────────────────
cat > "$DEPLOY_DIR/app/core/config.py" <<'PY'
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")
    supabase_url: str = ""
    supabase_service_key: str = ""
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_audience: str = "turbo-track"
    chatwoot_url: str = ""
    chatwoot_api_token: str = ""
    chatwoot_account_id: int = 1
    evolution_api_url: str = ""
    evolution_api_key: str = ""
    webhook_forward_url: str = ""

settings = Settings()
PY

# ── app/middleware/auth.py ────────────────────────────────────────────────────
cat > "$DEPLOY_DIR/app/middleware/auth.py" <<'PY'
from typing import Annotated
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from pydantic import BaseModel
from app.core.config import settings

class TokenPayload(BaseModel):
    sub: str
    tenant_id: str

_bearer = HTTPBearer(auto_error=True)

def get_current_tenant(credentials: Annotated[HTTPAuthorizationCredentials, Depends(_bearer)]) -> TokenPayload:
    try:
        payload = jwt.decode(credentials.credentials, settings.jwt_secret,
                             algorithms=[settings.jwt_algorithm], audience=settings.jwt_audience)
    except JWTError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token",
                            headers={"WWW-Authenticate": "Bearer"}) from exc
    tenant_id = payload.get("tenant_id")
    sub = payload.get("sub")
    if not tenant_id or not sub:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token missing required claims",
                            headers={"WWW-Authenticate": "Bearer"})
    return TokenPayload(sub=sub, tenant_id=tenant_id)

CurrentTenant = Annotated[TokenPayload, Depends(get_current_tenant)]
PY

# ── app/db/supabase_client.py ─────────────────────────────────────────────────
cat > "$DEPLOY_DIR/app/db/supabase_client.py" <<'PY'
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
    client = get_supabase()
    response = client.table("mensagens").select("*").eq("tenant_id", tenant_id).limit(limit).execute()
    return response.data or []

def get_whatsapp_instance(instance_name: str) -> dict[str, Any] | None:
    client = get_supabase()
    response = client.table("whatsapp_instances").select("*").eq("instance_name", instance_name).eq("active", True).limit(1).execute()
    rows = response.data or []
    return rows[0] if rows else None

def get_instance_by_inbox(inbox_id: int) -> dict[str, Any] | None:
    client = get_supabase()
    response = client.table("whatsapp_instances").select("*").eq("chatwoot_inbox_id", inbox_id).eq("active", True).limit(1).execute()
    rows = response.data or []
    return rows[0] if rows else None

def insert_whatsapp_event(*, tenant_id: str, instance_name: str, remote_jid: str,
                          message_id: str, direction: str, message_type: str,
                          chatwoot_conversation_id: int | None) -> None:
    client = get_supabase()
    client.table("whatsapp_mensagens").upsert({
        "tenant_id": tenant_id, "instance_name": instance_name,
        "remote_jid": remote_jid, "message_id": message_id,
        "direction": direction, "message_type": message_type,
        "chatwoot_conversation_id": chatwoot_conversation_id,
    }, on_conflict="message_id", ignore_duplicates=True).execute()
PY

# ── app/services/evolution.py ────────────────────────────────────────────────
cat > "$DEPLOY_DIR/app/services/evolution.py" <<'PY'
import logging
import httpx
from app.core.config import settings

logger = logging.getLogger(__name__)
_TIMEOUT = httpx.Timeout(10.0)

def _headers():
    return {"apikey": settings.evolution_api_key, "Content-Type": "application/json"}

def send_text_message(*, instance: str, phone: str, text: str) -> None:
    phone_clean = "".join(c for c in phone if c.isdigit())
    url = f"{settings.evolution_api_url}/message/sendText/{instance}"
    with httpx.Client(timeout=_TIMEOUT) as client:
        r = client.post(url, headers=_headers(), json={"number": phone_clean, "text": text})
        r.raise_for_status()
        logger.info("Sent WhatsApp message via %s to %s", instance, phone_clean)
PY

# ── app/services/chatwoot.py ──────────────────────────────────────────────────
cat > "$DEPLOY_DIR/app/services/chatwoot.py" <<'PY'
import logging
import httpx
from app.core.config import settings

logger = logging.getLogger(__name__)
_TIMEOUT = httpx.Timeout(10.0)

def _headers():
    return {"api_access_token": settings.chatwoot_api_token, "Content-Type": "application/json"}

def _base():
    return f"{settings.chatwoot_url}/api/v1/accounts/{settings.chatwoot_account_id}"

def find_or_create_contact(*, phone: str, name: str) -> int:
    with httpx.Client(timeout=_TIMEOUT) as client:
        r = client.get(f"{_base()}/contacts/search", headers=_headers(), params={"q": phone, "page": 1})
        r.raise_for_status()
        results = r.json().get("payload", [])
        if results:
            return results[0]["id"]
        r = client.post(f"{_base()}/contacts", headers=_headers(),
                        json={"name": name or phone, "phone_number": f"+{phone}"})
        r.raise_for_status()
        return r.json()["id"]

def find_or_create_conversation(*, contact_id: int, inbox_id: int) -> int:
    with httpx.Client(timeout=_TIMEOUT) as client:
        r = client.get(f"{_base()}/contacts/{contact_id}/conversations", headers=_headers())
        r.raise_for_status()
        for conv in r.json().get("payload", []):
            if conv.get("inbox_id") == inbox_id and conv.get("status") in ("open", "pending"):
                return conv["id"]
        r = client.post(f"{_base()}/conversations", headers=_headers(),
                        json={"contact_id": contact_id, "inbox_id": inbox_id})
        r.raise_for_status()
        return r.json()["id"]

def post_message(*, conversation_id: int, content: str, message_type: str = "incoming") -> None:
    with httpx.Client(timeout=_TIMEOUT) as client:
        r = client.post(f"{_base()}/conversations/{conversation_id}/messages", headers=_headers(),
                        json={"content": content, "message_type": message_type, "private": False})
        r.raise_for_status()
PY

# ── app/api/webhook.py ────────────────────────────────────────────────────────
cat > "$DEPLOY_DIR/app/api/webhook.py" <<'PY'
import logging
from typing import Any
import httpx
from fastapi import APIRouter, BackgroundTasks, HTTPException, Path, Request
from app.core.config import settings
from app.db.supabase_client import get_instance_by_inbox, get_whatsapp_instance, insert_whatsapp_event
from app.services.chatwoot import find_or_create_contact, find_or_create_conversation, post_message
from app.services.evolution import send_text_message

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/webhook", tags=["webhook"])
_FORWARD_TIMEOUT = httpx.Timeout(5.0)

def _extract_text(message: dict[str, Any]) -> str:
    return (message.get("conversation") or
            message.get("extendedTextMessage", {}).get("text", "") or
            message.get("imageMessage", {}).get("caption", "") or
            message.get("videoMessage", {}).get("caption", "") or "[mídia]")

def _phone_from_jid(jid: str) -> str:
    return jid.split("@")[0]

def _process_event(instance: str, payload: dict[str, Any]) -> None:
    event = payload.get("event", "")
    if "message" not in event.lower():
        return
    data = payload.get("data", {})
    key = data.get("key", {})
    remote_jid: str = key.get("remoteJid", "")
    from_me: bool = key.get("fromMe", False)
    message_id: str = key.get("id", "")
    push_name: str = data.get("pushName", "")
    message_obj: dict = data.get("message", {})
    message_type: str = data.get("messageType", "unknown")
    if "@g.us" in remote_jid:
        return
    if not remote_jid or not message_id:
        return
    phone = _phone_from_jid(remote_jid)
    text = _extract_text(message_obj)
    direction = "outbound" if from_me else "inbound"
    instance_cfg = get_whatsapp_instance(instance)
    if not instance_cfg:
        logger.warning("No whatsapp_instances row for instance=%s", instance)
        return
    tenant_id: str = instance_cfg["tenant_id"]
    inbox_id: int = instance_cfg["chatwoot_inbox_id"]
    chatwoot_conversation_id: int | None = None
    try:
        contact_id = find_or_create_contact(phone=phone, name=push_name)
        chatwoot_conversation_id = find_or_create_conversation(contact_id=contact_id, inbox_id=inbox_id)
        post_message(conversation_id=chatwoot_conversation_id, content=text,
                     message_type="outgoing" if from_me else "incoming")
    except Exception:
        logger.exception("Chatwoot error for message_id=%s", message_id)
    try:
        insert_whatsapp_event(tenant_id=tenant_id, instance_name=instance, remote_jid=remote_jid,
                              message_id=message_id, direction=direction, message_type=message_type,
                              chatwoot_conversation_id=chatwoot_conversation_id)
    except Exception:
        logger.exception("Supabase insert error for message_id=%s", message_id)
    if settings.webhook_forward_url:
        try:
            with httpx.Client(timeout=_FORWARD_TIMEOUT) as client:
                client.post(settings.webhook_forward_url, json=payload)
        except Exception:
            logger.warning("Forward to %s failed", settings.webhook_forward_url)

def _process_chatwoot_event(payload: dict[str, Any]) -> None:
    if payload.get("event") != "message_created":
        return
    if payload.get("message_type") != "outgoing":
        return
    if payload.get("sender", {}).get("type") != "user":
        return
    content: str = payload.get("content", "")
    if not content or not content.strip():
        return
    conversation = payload.get("conversation", {})
    inbox_id = conversation.get("inbox_id")
    contact_phone: str = conversation.get("meta", {}).get("sender", {}).get("phone_number", "")
    if not inbox_id or not contact_phone:
        logger.warning("Chatwoot webhook missing inbox_id or phone — skipped")
        return
    instance_cfg = get_instance_by_inbox(inbox_id)
    if not instance_cfg:
        logger.warning("No whatsapp_instances for chatwoot_inbox_id=%s — skipped", inbox_id)
        return
    try:
        send_text_message(instance=instance_cfg["instance_name"], phone=contact_phone, text=content)
    except Exception:
        logger.exception("Evolution API send error for inbox_id=%s", inbox_id)

@router.post("/evolution/{instance}")
async def evolution_webhook(instance: str = Path(...), request: Request = ...,
                            background_tasks: BackgroundTasks = ...) -> dict[str, str]:
    try:
        raw = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON body") from exc
    payload = raw.get("body", raw) if isinstance(raw.get("body"), dict) else raw
    background_tasks.add_task(_process_event, instance, payload)
    return {"status": "received"}

@router.post("/chatwoot")
async def chatwoot_webhook(request: Request = ..., background_tasks: BackgroundTasks = ...) -> dict[str, str]:
    try:
        payload = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON body") from exc
    background_tasks.add_task(_process_chatwoot_event, payload)
    return {"status": "received"}
PY

# ── app/main.py ───────────────────────────────────────────────────────────────
cat > "$DEPLOY_DIR/app/main.py" <<'PY'
from fastapi import FastAPI
from app.middleware.auth import CurrentTenant
from app.db.supabase_client import get_mensagens
from app.api.webhook import router as webhook_router

app = FastAPI(title="Turbo Track AI", version="0.1.0")
app.include_router(webhook_router)

@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "turbo-track-ai"}

@app.get("/mensagens")
def list_mensagens(tenant: CurrentTenant, limit: int = 100) -> dict:
    data = get_mensagens(tenant_id=tenant.tenant_id, limit=limit)
    return {"tenant_id": tenant.tenant_id, "count": len(data), "data": data}
PY

echo "=== All files created in $DEPLOY_DIR ==="
find "$DEPLOY_DIR" -type f | sort

echo ""
echo "=== Starting docker compose build + up ==="
cd "$DEPLOY_DIR"
docker compose up -d --build

echo ""
echo "=== Deploy complete. Checking container ==="
docker compose ps
