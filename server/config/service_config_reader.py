import json
import os
from typing import Dict, Any
from dataclasses import dataclass
# Initialize logger at the top so it's available everywhere 
from logger.loggerFactory import logger_factory
logger = logger_factory.get_logger('service_config_reader')

class ServiceConfigReader(Exception):
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

class ServiceConfigReader:
    """Read and manage service configuration from JSON file"""
    def __init__(self, config_file: str = None):
        """
        Initialize the configuration reader
        
        Args:
            config_file: Path to the JSON configuration file
                (defaults to $SERVICE_CONFIG_FILE, then config/service_config.json)
            
        Raises:
            ServiceConfigReader: If configuration file is not found or invalid
        """
        # SERVICE_CONFIG_FILE lets systemd point at the decrypted credential (see deployment/raspberry/templates)
        self.config_file = config_file or os.getenv('SERVICE_CONFIG_FILE', 'config/service_config.json')
        self.config: Dict[str, ServiceConfig] = {}
        self._load_config()
    
    def _load_config(self):
        """
        Load configuration from JSON file
        
        Raises:
            ServiceConfigReader: If file doesn't exist or JSON is invalid
        """
        logger.info(f"Loading service configuration from: {self.config_file} ...")
        
        # Check if file exists
        if not os.path.exists(self.config_file):
            raise ServiceConfigReader(f"Configuration file not found: {self.config_file}")
        
        try:
            with open(self.config_file, 'r') as f:
                config_data = json.load(f)
            
            # Validate and parse configuration
            self._parse_config(config_data)
            logger.info(f"Service configuration loaded successfully.")
            logger.info(f"  Services: {list(self.config.keys())}")
            
        except json.JSONDecodeError as e:
            raise ServiceConfigReader(f"Invalid JSON in configuration file: {str(e)}")
        except Exception as e:
            raise ServiceConfigReader(f"Failed to load configuration: {str(e)}")
    
    def _parse_config(self, config_data: Dict[str, Any]):
        """
        Parse configuration data and validate structure
        
        Args:
            config_data: Raw configuration data from JSON
            
        Raises:
            ServiceConfigReader: If configuration structure is invalid
        """
        if not isinstance(config_data, dict):
            raise ServiceConfigReader("Configuration must be a JSON object")
        
        if 'services' not in config_data:
            raise ServiceConfigReader("Configuration must contain 'services' field")
        
        services = config_data.get('services', {})
        
        if not isinstance(services, dict):
            raise ServiceConfigReader("'services' field must be a JSON object")
        
        if not services:
            logger.info("No services configured in configuration file")
            return
        
        # Parse each service
        for service_name, service_config in services.items():
            try:
                self._validate_service_config(service_name, service_config)
                srv_client_id=service_config['client_id']
                srv_client_secret=service_config['client_secret']
                # Create ServiceConfig object
                self.config[service_name] = ServiceConfig(
                    realm=service_config['realm'],
                    client_id=srv_client_id,
                    client_secret=srv_client_secret
                )
                logger.info(f"Loaded service configuration: {service_name}")
                
            except ServiceConfigReader as e:
                logger.error(f"Invalid configuration for service '{service_name}': {str(e)}")
                raise
    
    def _validate_service_config(self, service_name: str, service_config: Any):
        """
        Validate individual service configuration
        
        Args:
            service_name: Name of the service
            service_config: Service configuration object
            
        Raises:
            ServiceConfigReader: If configuration is invalid
        """
        if not isinstance(service_config, dict):
            raise ServiceConfigReader(f"Service '{service_name}' configuration must be a JSON object")
        
        required_fields = ['realm', 'client_id']
        
        for field in required_fields:
            if field not in service_config:
                raise ServiceConfigReader(f"Service '{service_name}' is missing required field: '{field}'")
            
            if not isinstance(service_config[field], str):
                raise ServiceConfigReader(f"Service '{service_name}' field '{field}' must be a string")
            
            if not service_config[field].strip():
                raise ServiceConfigReader(f"Service '{service_name}' field '{field}' cannot be empty")
    
    def get_service(self, service_name: str) -> ServiceConfig:
        """
        Get configuration for a specific service
        
        Args:
            service_name: Name of the service
            
        Returns:
            ServiceConfig object
            
        Raises:
            ServiceConfigReader: If service not found
        """
        if service_name not in self.config:
            available_services = list(self.config.keys())
            raise ServiceConfigReader(
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
            ServiceConfigReader: If configuration file is invalid
        """
        logger.info("Reloading configuration...")
        self.config.clear()
        self._load_config()
    
    def __repr__(self):
        """String representation of ConfigReader"""
        return f"ConfigReader(file={self.config_file}, services={list(self.config.keys())})"

# Convenience function for quick usage
def load_config(config_file: str = 'config.json') -> ServiceConfigReader:
    """
    Quick function to load configuration
    
    Args:
        config_file: Path to configuration file
        
    Returns:
        ConfigReader instance
        
    Raises:
        ServiceConfigReader: If configuration is invalid
    """
    return ServiceConfigReader(config_file)

####################################################
##### Initialize configuration reader instance #####
####################################################
serviceConfig = ServiceConfigReader()