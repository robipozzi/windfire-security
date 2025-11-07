import os
from typing import Any
from dotenv import load_dotenv

# Initialize logger at the top so it's available everywhere
# Use absolute imports from the client package root to make it usable as a module
from client.logger.loggingFactory import logger_factory
logger = logger_factory.get_logger('config-reader')

BOOLEANS=['ENFORCE_HTTPS', 'VERIFY_SSL_CERTS']

class ConfigError(Exception):
    """Custom exception for configuration errors"""
    pass

class ConfigReader:
    """Read and manage configuration from .env file"""
    def __init__(self):
        # Load environment from .env file
        load_dotenv()
    
    def get(self, key: str) -> Any:
        """
        Get an environment variable value by key.
        
        Args:
            key: Environment variable name
            
        Returns:
            The value of the environment variable or None if not set
        """
        if key in BOOLEANS:
            value = None
            raw = os.getenv(key)
            if isinstance(raw, str):
                normalized = raw.strip().lower()
                value = normalized in ('true', '1', 'yes', 'on')
            else:
                value = bool(raw)
            return value

        return os.getenv(key)
    
####################################################
##### Initialize configuration reader instance #####
####################################################
config = ConfigReader()