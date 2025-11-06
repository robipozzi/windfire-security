import logging
import logging.config
import json
import os
from log.colorFormatter import ColorFormatter

class LoggingFactory:
    env: str
    config_path: str
    default_level: int

    def __init__(self, default_level=logging.DEBUG):
        #print(f"====> START - __init__() called <====")
        self.env = os.getenv('ENVIRONMENT', 'prod')
        self.setup_logging()
        self.default_level = default_level

    def _config_path(self):
        return os.path.join(self.config_dir, self.config_filename_template.format(self.env))

    def setup_logging(self):
        """Setup logging configuration"""
        #print(f"====> START - setup_logging() called <====")
        """Setup logging based on environment"""
        #print(f"*** setup_logging - Environment: {self.env}")
        config_file = f'logging_config_{self.env}.json'
        self.config_path=f'config/{config_file}'
        #print(f"*** setup_logging - Using {self.config_path} for logging configuration")
        if os.path.exists(self.config_path):
            with open(self.config_path, 'r') as f:
                config = json.load(f)
            logging.config.dictConfig(config)
        else:
            logging.basicConfig(level=self.default_level)
            #print(f"Warning: {config_path} not found, using basic config")
        
        # Replace the formatter for the console handler
        console_handler = logging.getLogger('auth-service').handlers[0]
        console_handler.setFormatter(ColorFormatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s"))
        
        #print("*** Logging is configured.")
        #print(f"====> END - setup_logging called <====")
        return logging

    def get_logger(self, logger_name):
        """Ensure logging is configured and return a logger."""
        return logging.getLogger(logger_name)

###############################################
##### Initialize Logging Factory instance #####
###############################################
logger_factory = LoggingFactory()