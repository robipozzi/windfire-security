import os
import json
import logging
from logging.handlers import TimedRotatingFileHandler

class LoggerFactory:
    level: int
    logger: logging.Logger

    def __init__(self, level="DEBUG"):
        # If LOG_LEVEL environment variable is set, map it to a logging level constant
        # 
        # Supported levels:
        # DEBUG = 10, INFO = 20, WARNING = 30, ERROR = 40, CRITICAL = 50
        level_str = ""
        env_level = os.getenv("LOG_LEVEL")
        default_level = level  # Default log level if none is set in environment or settings
        #print(f"LOG_LEVEL environment variable: {env_level}")
        #print(f"DEFAULT_LOG_LEVEL: {default_level}")
        if env_level is not None and env_level != "":
            #print(f"LOG_LEVEL environment variable set: {env_level}")
            level_str = env_level.strip()
        elif default_level is not None and default_level != "":
            #print(f"LOG_LEVEL environment variable is not set: {env_level}")
            #print(f"Using DEFAULT_LOG_LEVEL: {default_level}")
            level_str = default_level.strip()

        try:
            #print(f"Parsing log level from string: {level_str}")
            if level_str.isdigit():
                level = int(level_str)
            else:
                level = {
                        "NOTSET": logging.NOTSET,
                        "DEBUG": logging.DEBUG,
                        "INFO": logging.INFO,
                        "WARNING": logging.WARNING,                            
                        "ERROR": logging.ERROR,
                        "CRITICAL": logging.CRITICAL,
                    }.get(level_str, level)
        except Exception:
            print(f"Invalid DEFAULT_LOG_LEVEL '{default_level}', using {level}")
            pass

        self.level = level
    
    def get_logger(self, logger_name):
        """Ensure logging is configured and return a logger."""
        self.logger = logging.getLogger(logger_name)
        file_handler = TimedRotatingFileHandler(
            os.getenv("DEFAULT_LOG_FILE", "windfire-security-server.log"), 
            when=os.getenv("DEFAULT_LOG_ROTATION_WHEN", "midnight"), 
            interval=1 / 86400, 
            backupCount=7
        )
        stream_handler = logging.StreamHandler()
        #file_handler.setFormatter(JsonFormatter())
        file_handler.setFormatter(ColorFormatter("%(asctime)s - %(levelname)s - %(name)s - %(message)s"))
        stream_handler.setFormatter(ColorFormatter("%(asctime)s - %(levelname)s - %(name)s - %(message)s"))
        self.logger.handlers = [file_handler]
        #print(f"Logger level set to: {self.level} for logger '{logger_name}'")
        self.logger.setLevel(self.level)
        return self.logger
        
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_record = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "module": record.module,
            "funcName": record.funcName,
            "lineno": record.lineno,
            "message": record.getMessage(),
        }
        return json.dumps(log_record)        

class ColorFormatter(logging.Formatter):
    COLORS = {
        'DEBUG': '\033[36m',    # Cyan
        'INFO': '\033[32m',     # Green
        'WARNING': '\033[33m',  # Yellow
        'ERROR': '\033[31m',    # Red
        'CRITICAL': '\033[41m', # Red background
    }
    RESET = '\033[0m'

    def format(self, record):
        color = self.COLORS.get(record.levelname, self.RESET)
        record.levelname = f"{color}{record.levelname}{self.RESET}"
        return super().format(record)
    
##############################################
##### Initialize Logger Factory instance #####
##############################################
logger_factory = LoggerFactory()