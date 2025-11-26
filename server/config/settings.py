import os
from typing import Any
from dotenv import load_dotenv # pyright: ignore[reportMissingImports]
# Initialize logger at the top so it's available everywhere 
from logger.loggerFactory import logger_factory
logger = logger_factory.get_logger('settings')

class Settings():
    """Read and manage configuration from .env file"""
    def __init__(self):
        """
        Initialize settings by loading .env file
        """
        self._load_env()
    
    def _load_env(self):
        """
        Load configuration from .env file
        """
        # Load environment from .env file
        logger.info(f"Loading environment from .env file ...")
        load_dotenv()
        logger.info(f"Configuration loaded successfully.")
        logger.info(f"  KEYCLOAK_SERVER_URL: {os.getenv('KEYCLOAK_SERVER_URL')}")
        logger.info(f"  ENFORCE_HTTPS: {os.getenv('ENFORCE_HTTPS')}")
        logger.info(f"  ALLOWED_HOSTS: {os.getenv('ALLOWED_HOSTS')}")
        
    def get(self, key: str) -> Any:
        """
        Get an environment variable value by key.
        
        Args:
            key: Environment variable name
            
        Returns:
            The value of the environment variable or None if not set
        """
        if key in 'ENFORCE_HTTPS':
            value = None
            raw = os.getenv(key)
            if isinstance(raw, str):
                normalized = raw.strip().lower()
                value = normalized in ('true', '1', 'yes', 'on')
            else:
                value = bool(raw)
            return value
        
        if key in 'API_PORT' or key in 'API_PORT_SECURE':
            raw = os.getenv(key)
            if raw is None or raw.strip() == '':
                return None
            try:
                return int(raw.strip())
            except (ValueError, TypeError):
                print(f"Invalid integer for {key}: {raw}")
            return None
        
        return os.getenv(key)

####################################################
##### Initialize configuration reader instance #####
####################################################
settings = Settings()