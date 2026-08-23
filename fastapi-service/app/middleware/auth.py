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


def get_current_tenant(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(_bearer)],
) -> TokenPayload:
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
            audience=settings.jwt_audience,
        )
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    tenant_id = payload.get("tenant_id")
    sub = payload.get("sub")
    if not tenant_id or not sub:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing required claims: tenant_id, sub",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return TokenPayload(sub=sub, tenant_id=tenant_id)


CurrentTenant = Annotated[TokenPayload, Depends(get_current_tenant)]
