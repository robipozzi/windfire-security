from fastapi import APIRouter # pyright: ignore[reportMissingImports]
# Initialize logger at the top so it's available everywhere 
from logger.loggerFactory import logger_factory
logger = logger_factory.get_logger('apiRouter')

api = APIRouter(prefix="/v1")
api_v2 = APIRouter(prefix="/v2")

# include routes to a root route
from routers.healthRouters import router as healthRouters
from routers.authRouters import router as authRouters
logger.debug("Including routers...")
api.include_router(healthRouters)
api.include_router(authRouters)