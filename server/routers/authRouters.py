from fastapi import HTTPException, status, Depends # pyright: ignore[reportMissingImports]
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials # pyright: ignore[reportMissingImports]
from fastapi.routing import APIRouter # pyright: ignore[reportMissingImports]
from fastapi.requests import Request # pyright: ignore[reportMissingImports]
from rateLimit import (AUTH_RATE_LIMIT, LOCKOUT_SECONDS, MAX_FAILURES, client_ip, failure_tracker,
                       limiter, too_many_attempts_response)
from keycloakAuth import KeycloakAuthError, authenticate_user, verify_token
from config.service_config_reader import ServiceConfigError
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
@limiter.limit(AUTH_RATE_LIMIT)
async def keycloak_login(request: Request, login_request: KeycloakLoginRequest):
    """
    Authenticate with Keycloak and receive tokens

    Rate limited per client IP (AUTH_RATE_LIMIT) and per username (lockout after repeated
    failures), both answering 429 with a Retry-After header: see rateLimit.py

    Args:
        login_request: username, password and service

    Returns:
        Access token and refresh token
    """
    logger.info(f"====> /v1/security/auth endpoint called for service: {login_request.service} <====")
    logger.debug(f"---> Function keycloak_login() called <---")
    ip = client_ip(request)
    user_key = failure_tracker.normalize(login_request.username)

    # Locked username: answer 429 without calling Keycloak
    lock_remaining = failure_tracker.lock_remaining(user_key)
    if lock_remaining > 0:
        logger.warning(f"Login rejected for locked username {user_key!r} from {ip}")
        return too_many_attempts_response(request, lock_remaining)

    try:
        # Authenticate with Keycloak
        logger.debug(f"---> Calling keycloakAuth authenticate_user() function <---")
        token_response = authenticate_user(
            login_request.username,
            login_request.password,
            login_request.service
        )

        failure_tracker.reset(user_key)
        logger.info(f"Login succeeded for {user_key!r} (service {login_request.service}) from {ip}")

        return KeycloakTokenResponse(
            access_token=token_response.get('access_token'),
            token_type="Bearer",
            expires_in=token_response.get('expires_in', 0),
            refresh_token=token_response.get('refresh_token'),
            refresh_expires_in=token_response.get('refresh_expires_in'),
            scope=token_response.get('scope')
        )
        
    except (KeycloakAuthError, ServiceConfigError) as e:
        # Audit line carries username and client IP only; the real cause goes to DEBUG and is
        # never returned (nor the list of configured services) to the caller
        logger.warning(f"Login failed for {user_key!r} from {ip}")
        logger.debug(f"Login failure cause for {user_key!r}: {str(e)}")
        if failure_tracker.record_failure(user_key):
            logger.warning(f"Username {user_key!r} locked for {LOCKOUT_SECONDS}s after {MAX_FAILURES} failed logins")
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
        logger.info(f"====> /v1/security/verify endpoint called for service: {tokenValidate.service} <====")
        logger.debug(f"---> Function verify() called <---")
        logger.debug(f"---> Calling keycloakAuth verify_token() function <---")
        token_claims = verify_token(credentials.credentials, service=service, method='local')
        return {"status": "valid"}
    except (KeycloakAuthError, ServiceConfigError) as e:
        # Log the real cause, but never return it (or the list of configured services) to the caller
        logger.warning(f"Token verification failed for service {tokenValidate.service}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token"
        )
    except Exception as e:
        logger.error(f"Token verification error for service {tokenValidate.service}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token"
        )
# ###############################################################
# ########### END - Keycloak Authentication endpoints ###########
# ###############################################################