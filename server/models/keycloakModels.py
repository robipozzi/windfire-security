from pydantic import BaseModel, Field # pyright: ignore[reportMissingImports]
from typing import Optional

# Pydantic models for Keycloak authentication requests and responses
class KeycloakLoginRequest(BaseModel):
    username: str = Field(..., description="Username")
    password: str = Field(..., description="Password")
    service: str = Field(..., description="Service")

class KeycloakTokenResponse(BaseModel):
    access_token: str
    token_type: str = "Bearer"
    expires_in: int
    refresh_token: Optional[str] = None
    refresh_expires_in: Optional[int] = None
    scope: Optional[str] = None

class KeycloakService(BaseModel):
    service: str