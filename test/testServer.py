from fastapi import FastAPI, HTTPException, Depends, status, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import uvicorn
from colorama import Fore, Style, init
from contextlib import asynccontextmanager
import os
import httpx

colorama_init = init(autoreset=True)

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
    Token is validated by calling the /verify endpoint on http://localhost:8000
    """
    print(f"====> /test endpoint called <====")

    # Ensure Authorization header contains a Bearer token
    if not credentials or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid authentication scheme",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = credentials.credentials

    # Verify token by calling the external verification endpoint
    verify_url = "http://localhost:8000/verify"
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(verify_url, headers={"Authorization": f"Bearer {token}"})
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

    try:
        payload = await request.json()
        print(f"Received JSON payload: {payload}")
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid JSON payload: {e}")

    if not isinstance(payload, dict):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="JSON payload must be an object")

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