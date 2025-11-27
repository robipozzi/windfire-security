from fastapi import HTTPException, status, Depends # pyright: ignore[reportMissingImports]
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials # pyright: ignore[reportMissingImports]
from fastapi.routing import APIRouter # pyright: ignore[reportMissingImports]
from keycloakAuth import KeycloakAuthError, authenticate_user, verify_token
from models.keycloakModels import KeycloakLoginRequest, KeycloakTokenResponse, KeycloakService
# Initialize logger at the top so it's available everywhere 
from logger.loggerFactory import logger_factory
logger = logger_factory.get_logger('authRouters')

router = APIRouter(prefix="/security", tags=["Security APIs"])

# Instantiates FastAPI’s HTTPBearer dependency 
# It extracts a Bearer token from the Authorization header of incoming requests. 
security = HTTPBearer()

# Security authentication endpoints
@router.post("/auth", response_model=KeycloakTokenResponse)
async def keycloak_login(login_request: KeycloakLoginRequest):
    """
    Authenticate with Keycloak and receive tokens
    
    Args:
        login_request: username, password and service
        
    Returns:
        Access token and refresh token
    """
    logger.info(f"====> /auth endpoint called for service: {login_request.service} <====")
    logger.debug(f"---> Function keycloak_login() called <---")
    logger.info(f"Keycloak login attempt for user {login_request.username} for service {login_request.service}")
    try:
        # Authenticate with Keycloak
        logger.debug(f"---> Calling keycloakAuth authenticate_user() function <---")
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

@router.post("/verify")
async def verify(tokenValidate: KeycloakService, credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        service = tokenValidate.service
        logger.debug(f"====> /verify endpoint called for service: {tokenValidate.service} <====")
        logger.debug(f"---> Function verify() called <---")
        logger.debug(f"---> Calling keycloakAuth verify_token() function <---")
        token_claims = verify_token(credentials.credentials, service=service, method='local')
        return {"status": "valid"}
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))
# ###############################################################
# ########### END - Keycloak Authentication endpoints ###########
# ###############################################################