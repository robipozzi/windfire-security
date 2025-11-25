import os
import requests # pyright: ignore[reportMissingModuleSource]
import jwt # pyright: ignore[reportMissingImports]
import json
from typing import Dict, Any
from datetime import datetime, timedelta
from config.settings import settings
# Initialize logger at the top so it's available everywhere 
from logger.loggerFactory import logger_factory
logger = logger_factory.get_logger('keycloakAuth')

class KeycloakAuthError(Exception):
    """Custom exception for Keycloak authentication errors"""
    pass

class KeycloakConfig:
    """Configuration for Keycloak connection"""
    def __init__(
        self,
        server_url: str = None,
        service: str = None,
    ):    
        self.server_url = server_url or os.getenv('KEYCLOAK_SERVER_URL')
        self.service = service
        servicecfg = None
        if not self.service is None:
            servicecfg = config.get_service(self.service)
            logger.debug(f"KeycloakConfig: got service config for {self.service}: {servicecfg}")
            self.realm = servicecfg.realm
            self.client_id = servicecfg.client_id
            self.client_secret = servicecfg.client_secret
        
        # Normalize server URL
        self.server_url = self.server_url.rstrip('/')
        
        # Token endpoints
        self.token_endpoint = f"{self.server_url}/realms/{self.realm}/protocol/openid-connect/token"
        self.userinfo_endpoint = f"{self.server_url}/realms/{self.realm}/protocol/openid-connect/userinfo"
        self.jwks_endpoint = f"{self.server_url}/realms/{self.realm}/protocol/openid-connect/certs"
        self.introspect_endpoint = f"{self.server_url}/realms/{self.realm}/protocol/openid-connect/token/introspect"

        logger.debug(f"KeycloakConfig: ")
        logger.debug(f"     server_url: {self.server_url}")
        logger.debug(f"     service: {self.service}")
        logger.debug(f"     realm: {self.realm}")
        logger.debug(f"     client_id: {self.client_id}")
        logger.debug(f"     token_endpoint: {self.token_endpoint}")
        logger.debug(f"     userinfo_endpoint: {self.userinfo_endpoint}")
        logger.debug(f"     jwks_endpoint: {self.jwks_endpoint}")
        logger.debug(f"     introspect_endpoint: {self.introspect_endpoint}")
    
    def validate(self):
        """Validate configuration"""
        if not self.server_url or not self.realm or not self.client_id:
            raise KeycloakAuthError("Missing required Keycloak configuration")
        logger.info(f"Keycloak configured: {self.server_url}/realms/{self.realm}")

class KeycloakAuth:
    """Keycloak authentication client"""
    def __init__(self, config: KeycloakConfig = None):
        self.config = config or KeycloakConfig()
        self.config.validate()
        self.access_token = None
        self.refresh_token = None
        self.token_expiry = None
        self.session = requests.Session()
        logger.info("KeycloakAuth client initialized")

    def authenticate_with_password(self, username: str, password: str) -> Dict[str, Any]:
        """
        Authenticate user with username and password (Resource Owner Password Credentials flow)
        
        Args:
            username: User's username
            password: User's password
            
        Returns:
            Dict with tokens and user info
            
        Raises:
            KeycloakAuthError: If authentication fails
        """
        logger.info(f"Authenticating user: {username}")
        
        payload = {
            'grant_type': 'password',
            'client_id': self.config.client_id,
            'username': username,
            'password': password
        }
        
        if self.config.client_secret:
            payload['client_secret'] = self.config.client_secret
        
        try:
            response = self.session.post(
                self.config.token_endpoint,
                data=payload,
                timeout=10
            )
            response.raise_for_status()
            
            token_data = response.json()
            self._store_tokens(token_data)
            
            logger.info(f"User {username} authenticated successfully")
            return token_data
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Authentication failed for user {username}: {str(e)}")
            raise KeycloakAuthError(f"Authentication failed: {str(e)}")
    
    def authenticate_with_client_credentials(self) -> Dict[str, Any]:
        """
        Authenticate as a service account using client credentials (Client Credentials flow)
        
        Returns:
            Dict with access token
            
        Raises:
            KeycloakAuthError: If authentication fails
        """
        logger.info(f"Authenticating with client credentials: {self.config.client_id}")
        
        if not self.config.client_secret:
            raise KeycloakAuthError("Client secret is required for client credentials flow")
        
        payload = {
            'grant_type': 'client_credentials',
            'client_id': self.config.client_id,
            'client_secret': self.config.client_secret
        }
        
        try:
            response = self.session.post(
                self.config.token_endpoint,
                data=payload,
                timeout=10
            )
            response.raise_for_status()
            
            token_data = response.json()
            self._store_tokens(token_data)
            
            logger.info("Service account authenticated successfully")
            return token_data
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Service account authentication failed: {str(e)}")
            raise KeycloakAuthError(f"Authentication failed: {str(e)}")
    
    def refresh_access_token(self, refresh_token: str = None) -> Dict[str, Any]:
        """
        Refresh access token using refresh token
        
        Args:
            refresh_token: Refresh token (uses stored token if not provided)
            
        Returns:
            Dict with new tokens
            
        Raises:
            KeycloakAuthError: If refresh fails
        """
        token_to_use = refresh_token or self.refresh_token
        
        if not token_to_use:
            raise KeycloakAuthError("No refresh token available")
        
        logger.info("Refreshing access token")
        
        payload = {
            'grant_type': 'refresh_token',
            'client_id': self.config.client_id,
            'refresh_token': token_to_use
        }
        
        if self.config.client_secret:
            payload['client_secret'] = self.config.client_secret
        
        try:
            response = self.session.post(
                self.config.token_endpoint,
                data=payload,
                timeout=10
            )
            response.raise_for_status()
            
            token_data = response.json()
            self._store_tokens(token_data)
            
            logger.info("Access token refreshed successfully")
            return token_data
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Token refresh failed: {str(e)}")
            raise KeycloakAuthError(f"Token refresh failed: {str(e)}")

    def get_user_info(self, access_token: str = None) -> Dict[str, Any]:
        """
        Get authenticated user information
        
        Args:
            access_token: Access token (uses stored token if not provided)
            
        Returns:
            Dict with user information
            
        Raises:
            KeycloakAuthError: If request fails
        """
        token = access_token or self.access_token
        
        if not token:
            raise KeycloakAuthError("No access token available")
        
        logger.info("Fetching user information")
        
        headers = {'Authorization': f'Bearer {token}'}
        
        try:
            response = self.session.get(
                self.config.userinfo_endpoint,
                headers=headers,
                timeout=10
            )
            response.raise_for_status()
            
            user_info = response.json()
            logger.info(f"User info retrieved for: {user_info.get('preferred_username')}")
            return user_info
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to fetch user info: {str(e)}")
            raise KeycloakAuthError(f"Failed to fetch user info: {str(e)}")

    def introspect_token(self, token: str, use_basic_auth: bool = True) -> Dict[str, Any]:
        """
        Introspect a token to check its validity and get claims
        
        Args:
            token: Token to introspect
            use_basic_auth: Use HTTP Basic Auth with client credentials (recommended)
            
        Returns:
            Dict with token information and validity
            
        Raises:
            KeycloakAuthError: If introspection fails
        """
        logger.info("Introspecting token")
        
        payload = {
            'token': token,
            'token_type_hint': 'access_token'
        }
        
        headers = {}
        auth = None
        
        # Use HTTP Basic Auth (recommended and more reliable)
        if use_basic_auth:
            if not self.config.client_secret:
                raise KeycloakAuthError("Client secret is required for token introspection")
            auth = (self.config.client_id, self.config.client_secret)
        else:
            # Alternative: include credentials in payload
            payload['client_id'] = self.config.client_id
            if self.config.client_secret:
                payload['client_secret'] = self.config.client_secret
        
        try:
            response = self.session.post(
                self.config.introspect_endpoint,
                data=payload,
                headers=headers,
                auth=auth,
                timeout=10
            )
            
            # Handle different response codes
            if response.status_code == 403:
                logger.error("Access denied: Client not allowed to introspect tokens. Check client roles in Keycloak.")
                raise KeycloakAuthError("Client not allowed to introspect tokens. Configure service account roles in Keycloak.")
            
            response.raise_for_status()
            
            introspection = response.json()
            is_active = introspection.get('active', False)
            logger.info(f"Token introspection - Active: {is_active}")
            return introspection
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Token introspection failed: {str(e)}")
            raise KeycloakAuthError(f"Token introspection failed: {str(e)}")
    
    def verify_token_locally(self, token: str) -> Dict[str, Any]:
        """
        Verify token locally using public keys (no introspection endpoint needed)
        This is the most reliable method as it doesn't require special client permissions
        
        Args:
            token: JWT token to verify
            
        Returns:
            Dict with decoded token claims
            
        Raises:
            KeycloakAuthError: If verification fails
        """
        logger.info("Verifying token locally using public keys")
        
        try:
            import json
            
            # Get unverified header to find kid
            unverified_header = jwt.get_unverified_header(token)
            kid = unverified_header.get('kid')
            
            if not kid:
                raise KeycloakAuthError("Token has no 'kid' in header")
            
            # Get public keys from Keycloak
            jwks = self.get_public_keys()
            
            # Find the matching public key
            public_key_data = None
            for key in jwks.get('keys', []):
                if key.get('kid') == kid:
                    public_key_data = key
                    break
            
            if not public_key_data:
                raise KeycloakAuthError(f"Public key with kid '{kid}' not found")
            
            # Convert JWK to PEM format - try multiple methods
            public_key = None
            
            # Method 1: Try PyJWT's RSAAlgorithm (PyJWT >= 2.0)
            try:
                from jwt.algorithms import RSAAlgorithm
                public_key = RSAAlgorithm.from_jwk(json.dumps(public_key_data))
                logger.debug("Using PyJWT RSAAlgorithm for key conversion")
            except (ImportError, AttributeError) as e:
                logger.debug(f"PyJWT RSAAlgorithm not available: {e}")
            
            # Method 2: Manual conversion using cryptography
            if public_key is None:
                try:
                    from cryptography.hazmat.primitives.asymmetric import rsa
                    from cryptography.hazmat.backends import default_backend
                    import base64
                    
                    if public_key_data.get('kty') != 'RSA':
                        raise KeycloakAuthError(f"Unsupported key type: {public_key_data.get('kty')}")
                    
                    # Decode base64url encoded components
                    def b64_decode(data):
                        padding = 4 - len(data) % 4
                        if padding != 4:
                            data += '=' * padding
                        return int.from_bytes(base64.urlsafe_b64decode(data), 'big')
                    
                    n = b64_decode(public_key_data['n'])  # modulus
                    e = b64_decode(public_key_data['e'])  # exponent
                    
                    # Create RSA public key
                    public_key = rsa.RSAPublicNumbers(e, n).public_key(default_backend())
                    logger.debug("Using manual cryptography conversion for key")
                    
                except Exception as e:
                    raise KeycloakAuthError(f"Failed to convert JWK to public key: {str(e)}")
            
            if public_key is None:
                raise KeycloakAuthError("Could not convert JWK to public key")
            
            # Decode and verify token
            # First try with audience verification
            try:
                decoded_token = jwt.decode(
                    token,
                    public_key,
                    algorithms=['RS256'],
                    audience=self.config.client_id,
                    options={"verify_signature": True, "verify_aud": True}
                )
            except jwt.InvalidAudienceError:
                # If audience validation fails, try without audience verification
                logger.warning(f"Token audience mismatch. Expected: {self.config.client_id}. Trying without audience verification...")
                decoded_token = jwt.decode(
                    token,
                    public_key,
                    algorithms=['RS256'],
                    options={"verify_signature": True, "verify_aud": False}
                )
            
            logger.info(f"Token verified successfully for user: {decoded_token.get('preferred_username')}")
            return decoded_token
            
        except jwt.ExpiredSignatureError:
            logger.error("Token has expired")
            raise KeycloakAuthError("Token has expired")
        except jwt.InvalidTokenError as e:
            logger.error(f"Token verification failed: {str(e)}")
            raise KeycloakAuthError(f"Invalid token: {str(e)}")
        except Exception as e:
            logger.error(f"Token verification error: {str(e)}")
            raise KeycloakAuthError(f"Token verification error: {str(e)}")



    def _________verify_token_locally(self, token: str) -> Dict[str, Any]:
        """
        Verify token locally using public keys (no introspection endpoint needed)
        This is the most reliable method as it doesn't require special client permissions
        
        Args:
            token: JWT token to verify
            
        Returns:
            Dict with decoded token claims
            
        Raises:
            KeycloakAuthError: If verification fails
        """
        logger.info("Verifying token locally using public keys")
        
        try:
            # Get unverified header to find kid
            unverified_header = jwt.get_unverified_header(token)
            kid = unverified_header.get('kid')
            
            if not kid:
                raise KeycloakAuthError("Token has no 'kid' in header")
            
            # Get public keys from Keycloak
            jwks = self.get_public_keys()
            
            # Find the matching public key
            public_key_data = None
            for key in jwks.get('keys', []):
                if key.get('kid') == kid:
                    public_key_data = key
                    break
            
            if not public_key_data:
                raise KeycloakAuthError(f"Public key with kid '{kid}' not found")
            
            # Convert JWK to PEM format
            try:
                # Try using PyJWT's built-in method first (works in PyJWT >= 2.0)
                from jwt.algorithms import RSAAlgorithm
                public_key = RSAAlgorithm.from_jwk(json.dumps(public_key_data))
            except (ImportError, AttributeError):
                # Fallback: manually convert JWK to RSA public key
                public_key = self._jwk_to_public_key(public_key_data)
            
            # **** FOR DEBUGGING PURPOSES ****
            # Decode without verification to see what's in the token
            unverified = jwt.decode(token, options={"verify_signature": False})
            logger.debug(f"Token claims: {unverified}")
            logger.debug(f"Audience claim: {unverified.get('aud')}")
            logger.debug(f"Client ID: {self.config.client_id}")
            # **** FOR DEBUGGING PURPOSES ****

            # Decode and verify token
            decoded_token = jwt.decode(
                token,
                public_key,
                algorithms=['RS256'],
                options={
                    "verify_signature": True,
                    "verify_aud": False  # Disable audience verification
                }
            )
            
            logger.info(f"Token verified successfully for user: {decoded_token.get('preferred_username')}")
            return decoded_token
            
        except jwt.ExpiredSignatureError:
            logger.error("Token has expired")
            raise KeycloakAuthError("Token has expired")
        except jwt.InvalidTokenError as e:
            logger.error(f"Token verification failed: {str(e)}")
            raise KeycloakAuthError(f"Invalid token: {str(e)}")
        except Exception as e:
            logger.error(f"Token verification error: {str(e)}")
            raise KeycloakAuthError(f"Token verification error: {str(e)}")
        
    def get_public_keys(self) -> Dict[str, Any]:
        """
        Get public keys for token verification (JWKS)
        
        Returns:
            Dict with public keys
            
        Raises:
            KeycloakAuthError: If retrieval fails
        """
        logger.info("Fetching public keys (JWKS)")
        
        try:
            response = self.session.get(
                self.config.jwks_endpoint,
                timeout=10
            )
            response.raise_for_status()
            
            keys = response.json()
            logger.info(f"Retrieved {len(keys.get('keys', []))} public keys")
            return keys
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to fetch public keys: {str(e)}")
            raise KeycloakAuthError(f"Failed to fetch public keys: {str(e)}")
    
    def logout(self, refresh_token: str = None):
        """
        Logout user and revoke tokens
        
        Args:
            refresh_token: Refresh token to revoke (uses stored token if not provided)
            
        Raises:
            KeycloakAuthError: If logout fails
        """
        token_to_revoke = refresh_token or self.refresh_token
        
        if not token_to_revoke:
            logger.warning("No refresh token available for logout")
            return
        
        logger.info("Logging out user")
        
        payload = {
            'client_id': self.config.client_id,
            'refresh_token': token_to_revoke
        }
        
        if self.config.client_secret:
            payload['client_secret'] = self.config.client_secret
        
        revoke_endpoint = f"{self.config.server_url}/realms/{self.config.realm}/protocol/openid-connect/revoke"
        
        try:
            response = self.session.post(
                revoke_endpoint,
                data=payload,
                timeout=10
            )
            response.raise_for_status()
            
            self.access_token = None
            self.refresh_token = None
            self.token_expiry = None
            
            logger.info("User logged out successfully")
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Logout failed: {str(e)}")
            raise KeycloakAuthError(f"Logout failed: {str(e)}")
    
    def is_token_expired(self) -> bool:
        """Check if current access token is expired"""
        if not self.token_expiry:
            return True
        return datetime.now() >= self.token_expiry
    
    def _store_tokens(self, token_data: Dict[str, Any]):
        """Store tokens and calculate expiry"""
        self.access_token = token_data.get('access_token')
        self.refresh_token = token_data.get('refresh_token')
        
        expires_in = token_data.get('expires_in', 300)
        self.token_expiry = datetime.now() + timedelta(seconds=expires_in)
        
        logger.debug(f"Tokens stored. Access token expires in {expires_in} seconds")
    
    def get_access_token(self) -> str:
        """Get current access token, refresh if expired"""
        if self.is_token_expired() and self.refresh_token:
            logger.info("Access token expired, refreshing...")
            self.refresh_access_token()
        
        if not self.access_token:
            raise KeycloakAuthError("No valid access token available")
        
        return self.access_token

# Convenience functions for quick usage
def authenticate_user(username: str, password: str, service: str) -> Dict[str, Any]:
        """Quick function to authenticate a user and return access token"""
        logger.debug(f"Authenticating user {username} for {service} service using quick function")
        config = KeycloakConfig(service=service)
        auth = KeycloakAuth(config)
        tokens = auth.authenticate_with_password(username, password)
        return tokens

def authenticate_service_account(config: KeycloakConfig = None) -> str:
    """Quick function to authenticate a service account and return access token"""
    auth = KeycloakAuth(config)
    tokens = auth.authenticate_with_client_credentials()
    return tokens['access_token']

def verify_token(token: str, service: str, method: str = 'local') -> Dict[str, Any]:
    """
    Quick function to verify a token
    
    Args:
        token: Token to verify
        config: Keycloak configuration
        method: 'local' (default, no special permissions needed) or 'introspect' (requires permissions)
    """
    config = KeycloakConfig(service=service)
    auth = KeycloakAuth(config)
    
    if method == 'local':
        return auth.verify_token_locally(token)
    else:
        return auth.introspect_token(token)