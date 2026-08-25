"""Evolution API client — outbound message sending."""

import logging

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)
_TIMEOUT = httpx.Timeout(10.0)


def _headers() -> dict[str, str]:
    return {"apikey": settings.evolution_api_key, "Content-Type": "application/json"}


def send_text_message(*, instance: str, phone: str, text: str) -> None:
    """Send a WhatsApp text message via Evolution API.

    phone may include a leading '+' — it is stripped before sending.
    """
    phone_clean = "".join(c for c in phone if c.isdigit())
    url = f"{settings.evolution_api_url}/message/sendText/{instance}"
    with httpx.Client(timeout=_TIMEOUT) as client:
        r = client.post(url, headers=_headers(), json={"number": phone_clean, "text": text})
        r.raise_for_status()
        logger.info("Sent WhatsApp message via %s to %s", instance, phone_clean)
