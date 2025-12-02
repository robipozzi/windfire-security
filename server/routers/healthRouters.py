from fastapi.routing import APIRouter # pyright: ignore[reportMissingImports]
from config.settings import settings
# Initialize logger at the top so it's available everywhere 
from logger.loggerFactory import logger_factory
logger = logger_factory.get_logger('healthRouters')

SERVICE_NAME = settings.get('APP_NAME')
router = APIRouter(prefix="/monitor", tags=["Monitor APIs"])

# Health check endpoint
@router.get("/health")
async def health_check():
    """
    Health check endpoint
    """
    logger.info("====> /v1/monitor/health endpoint called <====")
    return {"status": "healthy", "service": SERVICE_NAME}