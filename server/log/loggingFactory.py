import logging
import logging.config
import json
import os
from log.colorFormatter import ColorFormatter

def setup_logging():
    """Setup logging configuration"""
    #print(f"====> START - setup_logging() called <====")
    """Setup logging based on environment"""
    env = os.getenv('ENVIRONMENT', 'prod')
    #print(f"*** Environment: {env}")
    config_file = f'logging_config_{env}.json'
    config_path=f'config/{config_file}'
    #print(f"*** Using {config_path} for logging configuration")
    default_level=logging.DEBUG
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            config = json.load(f)
        logging.config.dictConfig(config)
    else:
        logging.basicConfig(level=default_level)
        #print(f"Warning: {config_path} not found, using basic config")
    
    # Replace the formatter for the console handler
    console_handler = logging.getLogger('auth-service').handlers[0]
    console_handler.setFormatter(ColorFormatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s"))
    
    #print("*** Logging is configured.")
    #print(f"====> END - setup_logging called <====")
    return logging

def get_logger(logger_name):
    #print("====> START - get_logger called <====")
    setup_logging()
    #print(f"*** Logger name: {logger_name}")
    logger = logging.getLogger(logger_name)
    #print("====> END - get_logger called <====")
    return logger