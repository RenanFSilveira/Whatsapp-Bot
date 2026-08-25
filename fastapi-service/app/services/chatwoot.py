"""Chatwoot API client — contact/conversation/message management."""

import logging

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

_TIMEOUT = httpx.Timeout(10.0)


def _headers() -> dict[str, str]:
    return {"api_access_token": settings.chatwoot_api_token, "Content-Type": "application/json"}


def _base() -> str:
    return f"{settings.chatwoot_url}/api/v1/accounts/{settings.chatwoot_account_id}"


def find_or_create_contact(*, phone: str, name: str) -> int:
    """Return Chatwoot contact id, creating it if it doesn't exist."""
    with httpx.Client(timeout=_TIMEOUT) as client:
        # Search by phone number
        r = client.get(
            f"{_base()}/contacts/search",
            headers=_headers(),
            params={"q": phone, "page": 1},
        )
        r.raise_for_status()
        results = r.json().get("payload", [])
        if results:
            return results[0]["id"]

        # Create new contact
        # Chatwoot wraps creation response under payload.contact
        r = client.post(
            f"{_base()}/contacts",
            headers=_headers(),
            json={"name": name or phone, "phone_number": f"+{phone}"},
        )
        r.raise_for_status()
        return r.json()["payload"]["contact"]["id"]


def find_or_create_conversation(*, contact_id: int, inbox_id: int) -> int:
    """Return an open conversation id for this contact/inbox, or create one."""
    with httpx.Client(timeout=_TIMEOUT) as client:
        # List conversations for this contact
        r = client.get(
            f"{_base()}/contacts/{contact_id}/conversations",
            headers=_headers(),
        )
        r.raise_for_status()
        for conv in r.json().get("payload", []):
            if conv.get("inbox_id") == inbox_id and conv.get("status") in ("open", "pending"):
                return conv["id"]

        # Create new conversation
        r = client.post(
            f"{_base()}/conversations",
            headers=_headers(),
            json={"contact_id": contact_id, "inbox_id": inbox_id},
        )
        r.raise_for_status()
        return r.json()["id"]


def post_message(*, conversation_id: int, content: str, message_type: str = "incoming") -> None:
    """Post a message to a Chatwoot conversation."""
    with httpx.Client(timeout=_TIMEOUT) as client:
        r = client.post(
            f"{_base()}/conversations/{conversation_id}/messages",
            headers=_headers(),
            json={"content": content, "message_type": message_type, "private": False},
        )
        r.raise_for_status()
