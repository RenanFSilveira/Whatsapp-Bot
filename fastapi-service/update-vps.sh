#!/bin/bash
# TurboTrack FastAPI — incremental update (outbound WhatsApp support)
# Run on VPS via SSH: bash update-vps.sh
set -e

DIR="/root/turbotrack-api"
cd "$DIR"

# 1. Update .env — add/update WEBHOOK_FORWARD_URL
if grep -q "WEBHOOK_FORWARD_URL" .env; then
  sed -i 's|WEBHOOK_FORWARD_URL=.*|WEBHOOK_FORWARD_URL=https://n8n.respondipravoce.com.br/webhook/whatsapp-grupos|' .env
else
  echo 'WEBHOOK_FORWARD_URL=https://n8n.respondipravoce.com.br/webhook/whatsapp-grupos' >> .env
fi
echo "✓ .env updated"

# 2. Create Evolution API service (send outbound messages)
cat > app/services/evolution.py <<'PY'
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
echo "✓ app/services/evolution.py created"

# 3. Add get_instance_by_inbox to supabase_client.py (if not already there)
if ! grep -q "get_instance_by_inbox" app/db/supabase_client.py; then
cat >> app/db/supabase_client.py <<'PY'

def get_instance_by_inbox(inbox_id: int):
    client = get_supabase()
    response = client.table("whatsapp_instances").select("*").eq("chatwoot_inbox_id", inbox_id).eq("active", True).limit(1).execute()
    rows = response.data or []
    return rows[0] if rows else None
PY
fi
echo "✓ app/db/supabase_client.py updated"

# 4. Fix Chatwoot contact creation response parsing (was r.json()["id"], correct is r.json()["payload"]["contact"]["id"])
sed -i 's/return r\.json()\["id"\]/return r.json()["payload"]["contact"]["id"]/' app/services/chatwoot.py
echo "✓ app/services/chatwoot.py bug fixed"

# 6. Overwrite webhook.py with bidirectional version
cat > app/api/webhook.py <<'PY'
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

def _extract_text(message):
    return (message.get("conversation") or
            message.get("extendedTextMessage", {}).get("text", "") or
            message.get("imageMessage", {}).get("caption", "") or
            message.get("videoMessage", {}).get("caption", "") or "[mídia]")

def _phone_from_jid(jid):
    return jid.split("@")[0]

def _process_event(instance, payload):
    event = payload.get("event", "")
    if "message" not in event.lower():
        return
    data = payload.get("data", {})
    key = data.get("key", {})
    remote_jid = key.get("remoteJid", "")
    from_me = key.get("fromMe", False)
    message_id = key.get("id", "")
    push_name = data.get("pushName", "")
    message_obj = data.get("message", {})
    message_type = data.get("messageType", "unknown")
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
    tenant_id = instance_cfg["tenant_id"]
    inbox_id = instance_cfg["chatwoot_inbox_id"]
    chatwoot_conversation_id = None
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

def _process_chatwoot_event(payload):
    if payload.get("event") != "message_created":
        return
    if payload.get("message_type") != "outgoing":
        return
    if payload.get("sender", {}).get("type") != "user":
        return
    content = payload.get("content", "")
    if not content or not content.strip():
        return
    conversation = payload.get("conversation", {})
    inbox_id = conversation.get("inbox_id")
    contact_phone = conversation.get("meta", {}).get("sender", {}).get("phone_number", "")
    if not inbox_id or not contact_phone:
        logger.warning("Chatwoot webhook missing inbox_id or phone — skipped")
        return
    instance_cfg = get_instance_by_inbox(inbox_id)
    if not instance_cfg:
        logger.warning("No whatsapp_instances for chatwoot_inbox_id=%s", inbox_id)
        return
    try:
        send_text_message(instance=instance_cfg["instance_name"], phone=contact_phone, text=content)
    except Exception:
        logger.exception("Evolution API send error for inbox_id=%s", inbox_id)

@router.post("/evolution/{instance}")
async def evolution_webhook(instance: str = Path(...), request: Request = ...,
                            background_tasks: BackgroundTasks = ...) -> dict:
    try:
        raw = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON body") from exc
    payload = raw.get("body", raw) if isinstance(raw.get("body"), dict) else raw
    background_tasks.add_task(_process_event, instance, payload)
    return {"status": "received"}

@router.post("/chatwoot")
async def chatwoot_webhook(request: Request = ..., background_tasks: BackgroundTasks = ...) -> dict:
    try:
        payload = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON body") from exc
    background_tasks.add_task(_process_chatwoot_event, payload)
    return {"status": "received"}
PY
echo "✓ app/api/webhook.py updated"

# 7. Rebuild and restart container
docker compose up -d --build

echo ""
echo "=== Update complete ==="
echo ""
echo "Next step — change Evolution API webhook to FastAPI (run this after container is up):"
echo ""
echo 'curl -s -X PUT https://evo.respondipravoce.com.br/webhook/set/Renan_Performance \'
echo '  -H "apikey: CD642396E2FE-482C-A642-1BABE4D84D0E" \'
echo '  -H "Content-Type: application/json" \'
echo '  -d '"'"'{"url":"https://api.respondipravoce.com.br/webhook/evolution/Renan_Performance","enabled":true,"events":["MESSAGES_UPSERT"],"webhookByEvents":false,"webhookBase64":false}'"'"
