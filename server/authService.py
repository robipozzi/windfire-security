import uvicorn
import os
from fastapi import FastAPI, HTTPException, Depends, status, Request
from fastapi.responses import RedirectResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.httpsredirect import HTTPSRedirectMiddleware 
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from keycloakAuth import KeycloakAuthError, authenticate_user, verify_token
from pydantic import BaseModel, Field
from typing import Optional
from contextlib import asynccontextmanager

# Initialize logger at the top so it's available everywhere
from logger.loggingFactory import logger_factory
logger = logger_factory.get_logger('auth-service')

# Load configuration 
from config.config_reader import config

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
    description="A secured SSL enforced REST API for security service operations",
    version="1.0.0",
    lifespan=lifespan,
    redirect_slashes=False
)

#####################################################
########## START - Security Configurations ##########
#####################################################
# Instantiates FastAPI’s HTTPBearer dependency 
# It extracts a Bearer token from the Authorization header of incoming requests. 
security = HTTPBearer()
# HTTPs enforcement and allowed hosts from config
ENFORCE_HTTPS = config.get('ENFORCE_HTTPS')
ALLOWED_HOSTS = config.get('ALLOWED_HOSTS').split(',')

# Custom HTTPS enforcement middleware
@app.middleware("http")
async def https_enforcement_middleware(request: Request, call_next):
    """
    Custom middleware to enforce HTTPS with exceptions for health checks
    """
    logger.debug(f"Custom middleware to enforce HTTPS with exceptions for health checks")
    # Skip HTTPS check for health endpoint (useful for load balancers)
    if request.url.path == "/health":
        logger.debug("Health check endpoint accessed, skipping HTTPS enforcement")
        response = await call_next(request)
        return response
    
    # Check if HTTPS enforcement is enabled
    if ENFORCE_HTTPS == True:
        # Check if request is HTTPS
        # Note: When behind a proxy/load balancer, check X-Forwarded-Proto header
        logger.debug(f"ENFORCE_HTTPS is {ENFORCE_HTTPS}. Checking if request is HTTPS ...")
        is_https = (
            request.url.scheme == "https" or
            request.headers.get("x-forwarded-proto") == "https" or
            request.headers.get("x-forwarded-ssl") == "on"
        )
        
        if not is_https:
            # Redirect HTTP to HTTPS
            logger.debug(f"Request is not HTTPS, redirecting HTTP to HTTPS")
            https_url = str(request.url).replace("http://", "https://", 1)
            logger.warning(f"🔒 Redirecting HTTP to HTTPS: {request.url.path}")
            return RedirectResponse(url=https_url, status_code=307)
    
    response = await call_next(request)
    
    # Add security headers to all responses
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    
    return response

# Add trusted host middleware if configured
if ALLOWED_HOSTS and ALLOWED_HOSTS != ['*']:
    logger.info(f"🛡️  Trusted hosts configured: {ALLOWED_HOSTS}")
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=ALLOWED_HOSTS)

# Log security configuration on startup
logger.debug(f"ENFORCE_HTTPS set to: {ENFORCE_HTTPS}")
if ENFORCE_HTTPS == True:
    logger.info("🔒 HTTPS enforcement enabled - all HTTP requests will be redirected to HTTPS")
else:
    logger.warning("⚠️  HTTPS enforcement disabled - API accessible via HTTP (not recommended for production)")
###################################################
########## END - Security Configurations ##########
###################################################

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
    return {"status": "healthy", "service": SERVICE_NAME, "authenication": "no", "https_enforced": {ENFORCE_HTTPS}}

# Main entry point
if __name__ == "__main__":
    logger.info("Starting Windfire Security FastAPI server...")
    # Get SSL configuration from environment variables
    ssl_keyfile = config.get('SSL_KEYFILE')
    ssl_certfile = config.get('SSL_CERTFILE')
    host=config.get('API_HOST')
    port = int(config.get('API_PORT'))
    
    # Determine if SSL is configured
    use_ssl = ssl_keyfile and ssl_certfile
    
    if use_ssl:
        if not os.path.exists(ssl_keyfile):
            logger.error(f"SSL key file not found: {ssl_keyfile}")
            exit(1)
        if not os.path.exists(ssl_certfile):
            logger.error(f"SSL certificate file not found: {ssl_certfile}")
            exit(1)
        
        logger.info(f"🔒 Starting server with HTTPS on {host}:{port}")
        logger.info(f"   SSL Key: {ssl_keyfile}")
        logger.info(f"   SSL Cert: {ssl_certfile}")
        
        uvicorn.run(
            app,
            host=host,
            port=port,
            ssl_keyfile=ssl_keyfile,
            ssl_certfile=ssl_certfile
        )
    else:
        if ENFORCE_HTTPS:
            logger.warning("⚠️  ENFORCE_HTTPS is enabled but no SSL certificates configured!")
            logger.warning("   Set SSL_KEYFILE and SSL_CERTFILE environment variables")
            logger.warning("   or disable ENFORCE_HTTPS for development")
        
        logger.info(f"🌐 Starting server with HTTP on {host}:{port}")
        logger.warning("⚠️  Running without SSL - not recommended for production")
        
        uvicorn.run(
            app,
            host=host,
            port=port
        )