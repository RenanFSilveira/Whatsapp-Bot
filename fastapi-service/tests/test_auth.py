import pytest
from fastapi.testclient import TestClient
from jose import jwt

from app.core.config import settings
from app.main import app

client = TestClient(app)


def _make_token(tenant_id: str, sub: str = "user-1") -> str:
    return jwt.encode(
        {"sub": sub, "tenant_id": tenant_id, "aud": settings.jwt_audience},
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


def test_mensagens_requires_auth():
    response = client.get("/mensagens")
    # HTTPBearer returns 401/403 depending on FastAPI version when no token is sent
    assert response.status_code in (401, 403)


def test_mensagens_rejects_invalid_token():
    response = client.get("/mensagens", headers={"Authorization": "Bearer not-a-real-token"})
    assert response.status_code == 401


def test_mensagens_accepts_valid_token(mocker):
    mocker.patch("app.main.get_mensagens", return_value=[{"id": 1, "tenant_id": "tenant-abc"}])
    token = _make_token("tenant-abc")
    response = client.get("/mensagens", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    body = response.json()
    assert body["tenant_id"] == "tenant-abc"


def test_tenant_isolation(mocker):
    """Verify get_mensagens is always called with the token's tenant_id."""
    mock = mocker.patch("app.main.get_mensagens", return_value=[])
    token = _make_token("tenant-xyz")
    client.get("/mensagens", headers={"Authorization": f"Bearer {token}"})
    mock.assert_called_once_with(tenant_id="tenant-xyz", limit=100)


def test_token_missing_tenant_id():
    bad_token = jwt.encode(
        {"sub": "user-1", "aud": settings.jwt_audience},
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )
    response = client.get("/mensagens", headers={"Authorization": f"Bearer {bad_token}"})
    assert response.status_code == 401


@pytest.mark.skip(reason="requires SUPABASE credentials")
def test_mensagens_integration():
    token = _make_token("integration-tenant")
    response = client.get("/mensagens", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
