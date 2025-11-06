import uvicorn
import os
import httpx
from fastapi import FastAPI, HTTPException, Depends, status, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from colorama import Fore, Style, init
from contextlib import asynccontextmanager

colorama_init = init(autoreset=True)
verify_ssl = os.getenv("VERIFY_SSL_CERTS").lower() == "true"
authUrl = os.getenv("AUTH_URL", "https://localhost:8443")

# Application startup is managed by the lifespan context manager defined below.
SERVICE_NAME = "Windfire Security Test Server"
@asynccontextmanager
async def lifespan(app):
    """
    Lifespan event handler to initialize service on startup
    """
    try:
        print(f"{SERVICE_NAME} initialized successfully")
    except Exception as e:
        print.error(Style.BRIGHT + Fore.RED + f"Failed to initialize {SERVICE_NAME} {str(e)}")
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

# Secured test endpoint
@app.post("/test")
async def test_endpoint(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(HTTPBearer())
):
    """
    A test endpoint to verify server is running and a valid bearer token is provided.
    Token is validated by calling the /verify endpoint on https://localhost:8443
    """
    print(f"====> /test endpoint called <====")

    # Ensure Authorization header contains a Bearer token
    if not credentials or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid authentication scheme",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Read JSON payload from the request
    payload = None
    try:
        payload = await request.json()
        print(f"Received JSON payload: {payload}")
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid JSON payload: {e}")

    if not isinstance(payload, dict):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="JSON payload must be an object")

    # Verify token by calling the external verification endpoint
    try:
        url = authUrl + "/verify"
        token = credentials.credentials
        http_headers = {"Content-Type": "application/json",
                        "Authorization": f"Bearer {token}"}
        async with httpx.AsyncClient(timeout=5.0, verify=verify_ssl) as client:
            resp = await client.post(url, 
                                     json=payload, 
                                     headers=http_headers)
    except httpx.RequestError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Token verification service unavailable: {e}",
        )
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))

    if resp.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    print(f"Token verified successfully with response: {resp.json()}")
    return {"message": "Test endpoint reached successfully"}

# Health check endpoint
@app.get("/health")
async def health_check():
    """
    Health check endpoint
    """
    print(f"====> /health endpoint called <====")
    return {"status": "healthy", "service": SERVICE_NAME}

# Main entry point
if __name__ == "__main__":
    print("Starting FastAPI server...")
    uvicorn.run(app, host="0.0.0.0", port=8001)