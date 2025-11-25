import os
from typing import Any
from dotenv import load_dotenv # pyright: ignore[reportMissingImports]

class Settings():
    """Read and manage configuration from .env file"""
    def __init__(self):
        """
        Initialize the configuration reader
        """
        self._load_config()
    
    def _load_config(self):
        """
        Load configuration from .env file
        """
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