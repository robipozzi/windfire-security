##### TERMINAL COLORS - START
# ===== COLOR CODES =====
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED=$'\e[1;31m'
MAGENTA=$'\e[1;35m'
BLU=$'\e[1;34m'
CYAN=$'\e[1;36m'
RESET='\033[0m'
BOLD='\033[1m'
# ===== EMOJI =====
coffee=$'\xE2\x98\x95'
coffee3="${coffee} ${coffee} ${coffee}"
##### TERMINAL COLORS - END

###### Variable section - START
PYTORCH_SERVER_VIRTUAL_ENV=windfire-security-server
PYTORCH_TEST_VIRTUAL_ENV=windfire-security-test
DEFAULT_USERNAME=windfire
DEFAULT_AUTH_SERVICE_TEST=windfire-calendar-srv
VERIFY_SSL_CERTS=true
WINDFIRE_ROOT_CA_KEY="WindfireRootCA.key"
WINDFIRE_ROOT_CA_CERTIFICATE="WindfireRootCA.crt"
WINDFIRE_DEFAULT_TRUSTSTORE_DIR=$HOME/opt/windfire/ssl/truststore

## Keycloak settings
KEYCLOAK_HOME=/Users/robertopozzi/software/keycloak-23.0.3
KEYCLOAK_DOCKER_IMAGE=quay.io/keycloak/keycloak
KEYCLOAK_DOCKER_IMAGE_VERSION=23.0.3
KEYCLOAK_CONTAINER_NAME=keycloak
KEYCLOAK_SERVER_ADDRESS=localhost
KEYCLOAK_SERVER_PORT=8080
KEYCLOAK_TLS_SERVER_PORT=8443
KEYCLOAK_USERNAME=admin
## Keycloak Security settings
DEFAULT_TLS_DIR=$HOME/dev/windfire-security/keycloak/security/tls
DEFAULT_KEYSTORE=server.keystore
DEFAULT_KEYSTORE_ALIAS=keycloak
DEFAULT_VALIDITY=1000
DEFAULT_CSR=keycloak.csr

# Certificate authority settings
DEFAULT_CA_KEYSTORE=ca_keycloak.jks
DEFAULT_CA_ALIAS=ca_keycloak
DEFAULT_CACERT=ca_keycloak.cer
DEFAULT_CACERT_PEM=ca_keycloak.pem

# Signed certificate settings
DEFAULT_SERVER_CERTIFICATE=keycloak.cer

# Truststore settings
DEFAULT_TRUSTSTORE_DIR=$HOME/opt/keycloak/ssl/truststore
DEFAULT_TRUSTSTORE=keycloak.truststore.jks
DEFAULT_PKCS12_TRUSTSTORE=keycloak.truststore.p12
DEFAULT_PEM_TRUSTSTORE=keycloak.truststore.pem
###### Variable section - END