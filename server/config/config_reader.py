import json
import os
from typing import Dict, Any
from dataclasses import dataclass
from log import loggingFactory
from dotenv import load_dotenv

# Initialize logger at the top so it's available everywhere
logger = loggingFactory.get_logger('config-reader')

# Load environment from .env file
load_dotenv()

class ConfigError(Exception):
    """Custom exception for configuration errors"""
    pass

@dataclass
class ServiceConfig:
    """Dataclass representing a service configuration"""
    realm: str
    client_id: str
    client_secret: str
    
    def __repr__(self):
        """Safe representation that doesn't expose client_secret"""
        return f"ServiceConfig(realm={self.realm}, client_id={self.client_id}, client_secret={'***'})"

class ConfigReader:
    """Read and manage configuration from JSON file"""
    def __init__(self, config_file: str = 'config/config.json'):
        """
        Initialize the configuration reader
        
        Args:
            config_file: Path to the JSON configuration file
            
        Raises:
            ConfigError: If configuration file is not found or invalid
        """
        self.config_file = config_file
        self.config: Dict[str, ServiceConfig] = {}
        self._load_config()
    
    def _load_config(self):
        """
        Load configuration from JSON file
        
        Raises:
            ConfigError: If file doesn't exist or JSON is invalid
        """
        logger.info(f"Loading configuration from: {self.config_file} ...")
        
        # Check if file exists
        if not os.path.exists(self.config_file):
            raise ConfigError(f"Configuration file not found: {self.config_file}")
        
        try:
            with open(self.config_file, 'r') as f:
                config_data = json.load(f)
            
            # Validate and parse configuration
            self._parse_config(config_data)
            logger.info(f"Configuration loaded successfully. Services: {list(self.config.keys())}")
            
        except json.JSONDecodeError as e:
            raise ConfigError(f"Invalid JSON in configuration file: {str(e)}")
        except Exception as e:
            raise ConfigError(f"Failed to load configuration: {str(e)}")
    
    def _parse_config(self, config_data: Dict[str, Any]):
        """
        Parse configuration data and validate structure
        
        Args:
            config_data: Raw configuration data from JSON
            
        Raises:
            ConfigError: If configuration structure is invalid
        """
        if not isinstance(config_data, dict):
            raise ConfigError("Configuration must be a JSON object")
        
        if 'services' not in config_data:
            raise ConfigError("Configuration must contain 'services' field")
        
        services = config_data.get('services', {})
        
        if not isinstance(services, dict):
            raise ConfigError("'services' field must be a JSON object")
        
        if not services:
            logger.warning("No services configured in configuration file")
            return
        
        # Parse each service
        for service_name, service_config in services.items():
            try:
                self._validate_service_config(service_name, service_config)
                srv_client_id=service_config['client_id']
                srv_client_secret = os.getenv(f"{srv_client_id}_KEYCLOAK_CLIENT_SECRET")
                # Create ServiceConfig object
                self.config[service_name] = ServiceConfig(
                    realm=service_config['realm'],
                    client_id=srv_client_id,
                    client_secret=srv_client_secret
                )
                logger.info(f"Loaded service configuration: {service_name}")
                
            except ConfigError as e:
                logger.error(f"Invalid configuration for service '{service_name}': {str(e)}")
                raise
    
    def _validate_service_config(self, service_name: str, service_config: Any):
        """
        Validate individual service configuration
        
        Args:
            service_name: Name of the service
            service_config: Service configuration object
            
        Raises:
            ConfigError: If configuration is invalid
        """
        if not isinstance(service_config, dict):
            raise ConfigError(f"Service '{service_name}' configuration must be a JSON object")
        
        required_fields = ['realm', 'client_id']
        
        for field in required_fields:
            if field not in service_config:
                raise ConfigError(f"Service '{service_name}' is missing required field: '{field}'")
            
            if not isinstance(service_config[field], str):
                raise ConfigError(f"Service '{service_name}' field '{field}' must be a string")
            
            if not service_config[field].strip():
                raise ConfigError(f"Service '{service_name}' field '{field}' cannot be empty")
    
    def get_service(self, service_name: str) -> ServiceConfig:
        """
        Get configuration for a specific service
        
        Args:
            service_name: Name of the service
            
        Returns:
            ServiceConfig object
            
        Raises:
            ConfigError: If service not found
        """
        if service_name not in self.config:
            available_services = list(self.config.keys())
            raise ConfigError(
                f"Service '{service_name}' not found in configuration. "
                f"Available services: {available_services}"
            )
        
        return self.config[service_name]
    
    def get_all_services(self) -> Dict[str, ServiceConfig]:
        """
        Get all configured services
        
        Returns:
            Dictionary of all service configurations
        """
        return self.config.copy()
    
    def service_exists(self, service_name: str) -> bool:
        """
        Check if a service is configured
        
        Args:
            service_name: Name of the service
            
        Returns:
            True if service exists, False otherwise
        """
        return service_name in self.config
    
    def list_services(self) -> list:
        """
        Get list of all configured service names
        
        Returns:
            List of service names
        """
        return list(self.config.keys())
    
    def reload_config(self):
        """
        Reload configuration from file
        
        Raises:
            ConfigError: If configuration file is invalid
        """
        logger.info("Reloading configuration...")
        self.config.clear()
        self._load_config()
    
    def __repr__(self):
        """String representation of ConfigReader"""
        return f"ConfigReader(file={self.config_file}, services={list(self.config.keys())})"

# Convenience function for quick usage
def load_config(config_file: str = 'config.json') -> ConfigReader:
    """
    Quick function to load configuration
    
    Args:
        config_file: Path to configuration file
        
    Returns:
        ConfigReader instance
        
    Raises:
        ConfigError: If configuration is invalid
    """
    return ConfigReader(config_file)

# Example usage
if __name__ == "__main__":
    try:
        # Load configuration
        config_reader = load_config('config.json')
        
        # List all services
        print(f"\n📋 Available services: {config_reader.list_services()}")
        
        # Get specific service
        keycloak_config = config_reader.get_service('windfire-calendar-srv')
        print(f"\n🔐 Keycloak service config:")
        print(f"   Realm: {keycloak_config.realm}")
        print(f"   Client ID: {keycloak_config.client_id}")
        print(f"   Client Secret: (hidden for security)")
        
        # Access all services
        print(f"\n🔍 All services:")
        for service_name, service_config in config_reader.get_all_services().items():
            print(f"   - {service_name}: realm={service_config.realm}")
        
    except ConfigError as e:
        print(f"❌ Configuration Error: {str(e)}")
    except Exception as e:
        print(f"❌ Unexpected Error: {str(e)}")