import requests
from typing import Dict, Any

# Initialize logger at the top so it's available everywhere
# Use absolute imports from the client package root to make it usable as a module
from client.logger.loggingFactory import logger_factory
logger = logger_factory.get_logger('auth-client')

# Load configuration
# Use absolute imports from the client package root to make it usable as a module
from client.config.config_reader import config

class AuthClient:
    """Client for authentication and token verification"""
    def __init__(self):
        self.auth_server_host = config.get('AUTHENTICATION_SERVER_HOST')
        self.auth_server_port = config.get('AUTHENTICATION_SERVER_PORT')
        self.enforce_https = config.get('ENFORCE_HTTPS')
        self.verify_ssl_certs = config.get('VERIFY_SSL_CERTS')
        self.protocol = 'http'
        if self.enforce_https:
            self.protocol = 'https'
        self.url_base = f"{self.protocol}://{self.auth_server_host}:{self.auth_server_port}"
    
    ##########################################################
    ##### Function to authenticate user and obtain token #####
    ##########################################################
    def authenticate(self, username: str, password: str, service: str) -> Dict[str, Any]:
        """
        Function to authenticate a user and return access token
        
        Args:
            username: Username
            password: Password
            service: Service name
        
        Returns:
            Access token if authentication is successful, None otherwise
        """
        token = None
        logger.info(f"Authenticating user {username} for {service} service to obtain access token ...")
        url = f"{self.url_base}/auth"
        http_headers = {"Content-Type": "application/json"}
        logger.info(f"Calling endpoint {url} on Authentication Server ...")
        try:
            response = requests.post(url,
                                    json={'username': username, 
                                            'password': password, 
                                            'service': service},
                                    headers=http_headers,
                                    verify=self.verify_ssl_certs)
            token = response.json()['access_token']
            logger.debug(f"Return Code: {response.status_code}\n")
            # ****** START - Uncomment for debug purposes in development ONLY ********
            #logger.debug(f"Response Body: {response.__dict__}\n")
            #logger.debug(f"Access Token: {token}\n")
            # ****** END - Uncomment for debug purposes in development ONLY ********
            if not token is None:
                logger.info("Authentication successful !!!")
        except Exception:
            token = None
            logger.error("Authentication failed")
            logger.debug(f"Response: {response.__dict__} \n")
            logger.debug("POST Status Code:", response.status_code) 
        return token
    
    #############################################
    ##### Function to verify token validity #####
    #############################################
    def verify(self, token: str, service: str, method: str = 'local') -> bool:
        """
        Function to verify authentication token validity
        
        Args:
            token: Access token to verify
            service: Service name
            method: Verification method ('local' or 'remote')
        
        Returns:
            Verification response as a dictionary
        """
        logger.info(f"Verifying authentication token validity for {service} service ...")
        url = f"{self.url_base}/verify"
        http_headers = {"Content-Type": "application/json",
                        "Authorization": f"Bearer {token}"}
        logger.info(f"Calling endpoint {url} on Authentication Server ...")
        verification_response = None
        try:
            response = requests.post(url, 
                                     json={'service': service}, 
                                     headers=http_headers,
                                     verify=self.verify_ssl_certs)
            verification_response = response.json()
            logger.debug(f"Return Code: {response.status_code}\n")
            # ****** START - Uncomment for debug purposes in development ONLY ********
            #logger.debug(f"Response Body: {response.__dict__}\n")
            #logger.debug(f"Verification Response: {verification_response}\n")
            # ****** END - Uncomment for debug purposes in development ONLY ********
            if response.status_code == 200:
                logger.info("Token verification successful !!!")
            else:
                logger.warning("Token verification failed !!!")
        except Exception:
            verification_response = None
            logger.error("Token verification failed")
            logger.debug(f"Response: {response.__dict__} \n")
            logger.debug("POST Status Code:", response.status_code) 
        return True if verification_response and response.status_code == 200 else False

####################################################
##### Initialize configuration reader instance #####
####################################################
authClient = AuthClient()

# Quick test when run as main module
if __name__ == "__main__":
    logger.info("Running authClient quick test ...")
    logger.info(f"Environment: {config.get('ENVIRONMENT')}")
    logger.info(f"Auth Server Host: {authClient.auth_server_host}")
    logger.info(f"Auth Server Port: {authClient.auth_server_port}")
    logger.info(f"ENFORCE_HTTPS: {authClient.enforce_https}")
    logger.info(f"VERIFY_SSL_CERTS: {authClient.verify_ssl_certs}")
    if authClient.enforce_https:
        logger.info("HTTPS is enforced for communication with the authentication server.")
    if not authClient.verify_ssl_certs:
        logger.warning("SSL certificate verification is DISABLED. This is insecure and not recommended for production environments.")
    # Quick test of authentication and verification
    username = config.get('USERNAME')
    password = config.get('PASSWORD')
    service = config.get('SERVICE')
    token = authClient.authenticate(username, password, service)
    isTokenValid = authClient.verify(token, service)
    logger.info(f"Token valid: {isTokenValid}")