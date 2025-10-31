from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from keycloakAuth import KeycloakAuthError
from keycloakAuth import authenticate_user, verify_token
import uvicorn
from pydantic import BaseModel, Field
from typing import Optional
from log import loggingFactory
from contextlib import asynccontextmanager
from typing import Optional

# Initialize logger at the top so it's available everywhere
logger = loggingFactory.get_logger('auth-service')

# Security
security = HTTPBearer()

# Application startup is managed by the lifespan context manager defined below.
SERVICE_NAME = "Windfire Security Authentication Service"
@asynccontextmanager
async def lifespan(app):
    """
    Lifespan event handler to initialize service on startup
    """
    try:
        logger.info(f"{SERVICE_NAME} initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize {SERVICE_NAME} {str(e)}")
    yield
    # Add shutdown/cleanup logic here if needed

# Initialize FastAPI app
app = FastAPI(
    title=SERVICE_NAME,
    description="A secured REST API for security service operations",
    version="1.0.0",
    lifespan=lifespan,
    redirect_slashes=False
)

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

# ###############################################################
# ########## START - Keycloak Authentication endpoints ##########
# ###############################################################
@app.post("/auth", response_model=KeycloakTokenResponse)
async def keycloak_login(login_request: KeycloakLoginRequest):
    """
    Authenticate with Keycloak and receive tokens
    
    Args:
        login_request: username, password and service
        
    Returns:
        Access token and refresh token
    """
    logger.debug(f"====> /auth endpoint called for service: {login_request.service} <====")
    logger.info(f"Keycloak login attempt for user {login_request.username} for service {login_request.service}")
    try:
        # Authenticate with Keycloak
        token_response = authenticate_user(
            login_request.username,
            login_request.password,
            login_request.service
        )
        
        logger.info(f"User {login_request.username} authenticated successfully for {login_request.service} service with Keycloak")
        
        return KeycloakTokenResponse(
            access_token=token_response.get('access_token'),
            token_type="Bearer",
            expires_in=token_response.get('expires_in', 0),
            refresh_token=token_response.get('refresh_token'),
            refresh_expires_in=token_response.get('refresh_expires_in'),
            scope=token_response.get('scope')
        )
        
    except KeycloakAuthError as e:
        logger.warning(f"Keycloak authentication failed for user {login_request.username}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or password"
        )
    except Exception as e:
        logger.error(f"Keycloak authentication error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Authentication error"
        )

@app.post("/verify")
async def verify(tokenValidate: KeycloakService, credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        service = tokenValidate.service
        logger.debug(f"====> /verify endpoint called for service: {tokenValidate.service} <====")
        token_claims = verify_token(credentials.credentials, service=service, method='local')
        return {"status": "valid"}
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))
# ###############################################################
# ########### END - Keycloak Authentication endpoints ###########
# ###############################################################

# Health check endpoint
@app.get("/health")
async def health_check():
    """
    Health check endpoint
    """
    logger.debug(f"====> /health endpoint called <====")
    return {"status": "healthy", "service": SERVICE_NAME}

# Main entry point
if __name__ == "__main__":
    logger.info("Starting FastAPI server...")
    uvicorn.run(app, host="0.0.0.0", port=8000)