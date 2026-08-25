"""Evolution API webhook — receives MESSAGES_UPSERT and routes to Chatwoot + Supabase.
   Chatwoot webhook — receives outgoing agent replies and forwards to WhatsApp.
"""

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
    return (
        message.get("conversation")
        or message.get("extendedTextMessage", {}).get("text", "")
        or message.get("imageMessage", {}).get("caption", "")
        or message.get("videoMessage", {}).get("caption", "")
        or "[mídia]"
    )


def _phone_from_jid(jid: str) -> str:
    return jid.split("@")[0]


def _process_event(instance: str, payload: dict[str, Any]) -> None:
    """Inbound: Evolution API → Chatwoot + Supabase."""
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

    instance_cfg = get_whatsapp_instance(instance)
    if not instance_cfg:
        logger.warning("No whatsapp_instances row for instance=%s — skipped", instance)
        return

    tenant_id: str = instance_cfg["tenant_id"]
    inbox_id: int = instance_cfg["chatwoot_inbox_id"]

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

    # Forward to n8n (grupos flow) — fire-and-forget
    if settings.webhook_forward_url:
        try:
            with httpx.Client(timeout=_FORWARD_TIMEOUT) as client:
                client.post(settings.webhook_forward_url, json=payload)
        except Exception:
            logger.warning("Forward to %s failed", settings.webhook_forward_url)


def _process_chatwoot_event(payload: dict[str, Any]) -> None:
    """Outbound: Chatwoot agent reply → WhatsApp via Evolution API."""
    if payload.get("event") != "message_created":
        return
    if payload.get("message_type") != "outgoing":
        return
    # Only human agents — skip bots and automated messages
    sender_type = payload.get("sender", {}).get("type", "")
    if sender_type != "user":
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
        send_text_message(
            instance=instance_cfg["instance_name"],
            phone=contact_phone,
            text=content,
        )
    except Exception:
        logger.exception("Evolution API send error for inbox_id=%s", inbox_id)


@router.post("/evolution/{instance}")
async def evolution_webhook(
    instance: str = Path(..., description="Evolution API instance name"),
    request: Request = ...,
    background_tasks: BackgroundTasks = ...,
) -> dict[str, str]:
    """Receive Evolution API MESSAGES_UPSERT. Handles both direct and n8n-forwarded payloads."""
    try:
        raw = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON body") from exc

    # n8n wraps the original Evolution API payload under raw["body"] when forwarding
    payload = raw.get("body", raw) if isinstance(raw.get("body"), dict) else raw

    background_tasks.add_task(_process_event, instance, payload)
    return {"status": "received"}


@router.post("/chatwoot")
async def chatwoot_webhook(
    request: Request = ...,
    background_tasks: BackgroundTasks = ...,
) -> dict[str, str]:
    """Receive Chatwoot message_created webhook and send agent replies to WhatsApp."""
    try:
        payload = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON body") from exc

    background_tasks.add_task(_process_chatwoot_event, payload)
    return {"status": "received"}
