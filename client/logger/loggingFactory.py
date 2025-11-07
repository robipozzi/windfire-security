import logging
import logging.config
import json
import os
# Use absolute imports from the client package root to make it usable as a module
from client.logger.colorFormatter import ColorFormatter

class LoggingFactory:
    env: str
    config_path: str
    default_level: int

    def __init__(self, default_level=logging.DEBUG):
        #print(f"====> START - __init__() called <====")
        self.env = os.getenv('ENVIRONMENT', 'dev')
        self.default_level = default_level
        #print(f"*** __init__ - default_level: {self.default_level}")
        self.setup_logging()

    def _config_path(self):
        return os.path.join(self.config_dir, self.config_filename_template.format(self.env))

    def setup_logging(self):
        #print(f"====> START - setup_logging() called <====")
        
        """Setup logging based on environment"""
        #print(f"*** setup_logging - Environment: {self.env}")
        config_file = f'logger/logging_config_{self.env}.json'
        self.config_path=f'{config_file}'
        #print(f"*** setup_logging - Using {self.config_path} for logging configuration")
        if os.path.exists(self.config_path):
            with open(self.config_path, 'r') as f:
                config = json.load(f)
            logging.config.dictConfig(config)
        else:
            logging.basicConfig(level=self.default_level)
            #print(f"Warning: {self.config_path} not found, using basic config")
        
        """Set up logging configuration"""
        #print(f"*** getLogger - Setting up logger for 'auth-client'")
        logger = logging.getLogger('auth-client')
        
        # Replace the formatter for the console handler
        # Only configure if not already configured (check for existing handlers)
        if logger.handlers:
            #print(f"*** Logger already has handlers")
            for handler in logger.handlers:
                # Set ColorFormatter for console handler
                if isinstance(handler, logging.StreamHandler):
                    #print(f"*** Setting ColorFormatter for console handler")
                    handler.setFormatter(ColorFormatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s"))
            
            # Logger already has handlers, return
            return
        
        # Create console handler if no handlers exist
        #print(f"*** Creating console handler for logger.")
        console_handler = logging.StreamHandler()
        #print(f"*** Configuring ColorFormatter for console handler.")
        console_handler.setFormatter(ColorFormatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s"))
        
        # Add handler to logger
        logger.addHandler(console_handler)

        #print("*** Logging is configured.")
        #print(f"====> END - setup_logging called <====")
        return logger

    def get_logger(self, logger_name):
        """Ensure logging is configured and return a logger."""
        return logging.getLogger(logger_name)

###############################################
##### Initialize Logging Factory instance #####
###############################################
logger_factory = LoggingFactory()