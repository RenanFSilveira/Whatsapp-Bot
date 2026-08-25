"""Evolution API webhook — receives MESSAGES_UPSERT and routes to Chatwoot + Supabase."""

import logging
from typing import Any

import httpx
from fastapi import APIRouter, BackgroundTasks, HTTPException, Path, Request

from app.core.config import settings
from app.db.supabase_client import get_whatsapp_instance, insert_whatsapp_event
from app.services.chatwoot import find_or_create_contact, find_or_create_conversation, post_message

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/webhook", tags=["webhook"])

_FORWARD_TIMEOUT = httpx.Timeout(5.0)


def _extract_text(message: dict[str, Any]) -> str:
    """Extract readable text from an Evolution API message object."""
    return (
        message.get("conversation")
        or message.get("extendedTextMessage", {}).get("text", "")
        or message.get("imageMessage", {}).get("caption", "")
        or message.get("videoMessage", {}).get("caption", "")
        or "[mídia]"
    )


def _phone_from_jid(jid: str) -> str:
    """Strip @s.whatsapp.net / @g.us suffix and return plain phone number."""
    return jid.split("@")[0]


def _process_event(instance: str, payload: dict[str, Any]) -> None:
    """Core processing: write to Supabase + create Chatwoot message."""
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

    # Skip group messages
    if "@g.us" in remote_jid:
        return

    if not remote_jid or not message_id:
        logger.warning("Webhook missing remoteJid or id — skipped")
        return

    phone = _phone_from_jid(remote_jid)
    text = _extract_text(message_obj)
    direction = "outbound" if from_me else "inbound"

    # Look up instance config in Supabase
    instance_cfg = get_whatsapp_instance(instance)
    if not instance_cfg:
        logger.warning("No whatsapp_instances row for instance=%s — skipped", instance)
        return

    tenant_id: str = instance_cfg["tenant_id"]
    inbox_id: int = instance_cfg["chatwoot_inbox_id"]

    # Chatwoot: find/create contact and conversation, then post message
    chatwoot_conversation_id: int | None = None
    try:
        contact_id = find_or_create_contact(phone=phone, name=push_name)
        chatwoot_conversation_id = find_or_create_conversation(contact_id=contact_id, inbox_id=inbox_id)
        chatwoot_message_type = "outgoing" if from_me else "incoming"
        post_message(
            conversation_id=chatwoot_conversation_id,
            content=text,
            message_type=chatwoot_message_type,
        )
    except Exception:
        logger.exception("Chatwoot error for message_id=%s", message_id)

    # Supabase: lightweight routing record only
    try:
        insert_whatsapp_event(
            tenant_id=tenant_id,
            instance_name=instance,
            remote_jid=remote_jid,
            message_id=message_id,
            direction=direction,
            message_type=message_type,
            chatwoot_conversation_id=chatwoot_conversation_id,
        )
    except Exception:
        logger.exception("Supabase insert error for message_id=%s", message_id)

    # Forward to n8n (or any configured URL) — fire-and-forget
    if settings.webhook_forward_url:
        try:
            with httpx.Client(timeout=_FORWARD_TIMEOUT) as client:
                client.post(settings.webhook_forward_url, json=payload)
        except Exception:
            logger.warning("Forward to %s failed", settings.webhook_forward_url)


@router.post("/evolution/{instance}")
async def evolution_webhook(
    instance: str = Path(..., description="Evolution API instance name"),
    request: Request = ...,
    background_tasks: BackgroundTasks = ...,
) -> dict[str, str]:
    """Receive Evolution API MESSAGES_UPSERT webhook and process asynchronously."""
    try:
        payload = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON body") from exc

    background_tasks.add_task(_process_event, instance, payload)
    return {"status": "received"}
