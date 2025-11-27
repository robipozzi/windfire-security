import uvicorn # pyright: ignore[reportMissingImports]
import os
from fastapi import FastAPI, HTTPException, Depends, status, Request # pyright: ignore[reportMissingImports]
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials # pyright: ignore[reportMissingImports]
from colorama import Fore, Style, init # pyright: ignore[reportMissingModuleSource]
from contextlib import asynccontextmanager
# Import the AuthClient instance from the client package
from client.authClient import authClient

colorama_init = init(autoreset=True)
verify_ssl = os.getenv("VERIFY_SSL_CERTS").lower() == "true"

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
    description="A Test server to test secured REST API for security service operations",
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
    token = credentials.credentials
    print(Style.BRIGHT + Fore.BLUE + "Delegating token verification to authClient module ...")
    print(Style.BRIGHT + Fore.BLUE + "Calling client.authClient.verify() ...")
    isTokenValid = authClient.verify(token, service=payload.get("service"), method="remote")

    if not isTokenValid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    print(f"Token verified successfully for service: {payload.get('service')}")
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