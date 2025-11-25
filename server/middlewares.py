from fastapi.requests import Request # pyright: ignore[reportMissingImports]
from fastapi.responses import RedirectResponse # pyright: ignore[reportMissingImports]
from apiRouter import api
from config.settings import settings
# Initialize logger at the top so it's available everywhere 
from logger.loggerFactory import logger_factory
logger = logger_factory.get_logger('middlewares')

# =====> START - HTTPs enforcement middleware configuration <=====
ENFORCE_HTTPS = settings.get('ENFORCE_HTTPS')
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
# =====> END - HTTPs enforcement middleware configuration <=====