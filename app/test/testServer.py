import requests
from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import uvicorn
from colorama import Fore, Style, init
from contextlib import asynccontextmanager

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
async def test_endpoint():
    """
    A test endpoint to verify server is running
    """
    print(f"====> /test endpoint called <====")
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