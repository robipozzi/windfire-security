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
# ===== PYTHON VIRTUAL ENVIRONMENTS VARIABLES =====
PYTORCH_SERVER_VIRTUAL_ENV=windfire-security-server
PYTORCH_TEST_VIRTUAL_ENV=windfire-security-test
DEFAULT_USERNAME=windfire
DEFAULT_AUTH_SERVICE_TEST=windfire-calendar-srv
VERIFY_SSL_CERTS=true
# ===== ROOT CA VARIABLES =====
WINDFIRE_ROOT_CA_KEY="WindfireRootCA.key"
WINDFIRE_ROOT_CA_CERTIFICATE="WindfireRootCA.crt"
WINDFIRE_DEFAULT_KEYSTORE_DIR=$HOME/opt/windfire/ssl/keystore
WINDFIRE_DEFAULT_TRUSTSTORE_DIR=$HOME/opt/windfire/ssl/truststore
WINDFIRE_DEFAULT_CERTS_PROD_DIR=$HOME/opt/windfire/ssl/certs/raspberry

# ===== KEYCLOAK SETTINGS VARIABLES =====
KEYCLOAK_HOME=/Users/robertopozzi/software/keycloak-23.0.3
KEYCLOAK_DOCKER_IMAGE=quay.io/keycloak/keycloak
KEYCLOAK_DOCKER_IMAGE_VERSION=23.0.3
KEYCLOAK_CONTAINER_NAME=keycloak
KEYCLOAK_SERVER_ADDRESS=localhost
KEYCLOAK_SERVER_PORT=8080
KEYCLOAK_TLS_SERVER_PORT=8443
KEYCLOAK_USERNAME=admin

# ===== KEYCLOAK SECURITY SETTINGS VARIABLES =====
DEFAULT_TLS_DIR=$HOME/dev/windfire-security/keycloak/security/tls
DEFAULT_KEYSTORE=server.keystore
DEFAULT_KEYSTORE_ALIAS=keycloak
DEFAULT_VALIDITY=1000
DEFAULT_CSR=keycloak.csr

# ===== KEYCLOAK CERTIFICATE AUTHORITY SETTINGS VARIABLES =====
DEFAULT_CA_KEYSTORE=ca_keycloak.jks
DEFAULT_CA_ALIAS=ca_keycloak
DEFAULT_CACERT=ca_keycloak.cer
DEFAULT_CACERT_PEM=ca_keycloak.pem

# ===== KEYCLOAK SIGNED CERTIFICATE SETTINGS VARIABLES =====
DEFAULT_SERVER_CERTIFICATE=keycloak.cer

# ===== KEYCLOAK TRUSTSTORE SETTINGS VARIABLES =====
DEFAULT_TRUSTSTORE_DIR=$HOME/opt/keycloak/ssl/truststore
DEFAULT_TRUSTSTORE=keycloak.truststore.jks
DEFAULT_PKCS12_TRUSTSTORE=keycloak.truststore.p12
DEFAULT_PEM_TRUSTSTORE=keycloak.truststore.pem
###### Variable section - END

###### Function section - START
# Function to select and set programs run environment
selectEnvironment()
{
    ENVIRONMENT_SELECTION=$1
    if [[ -n "${ENVIRONMENT_SELECTION}" ]]; then
        echo 
        return
    else
        echo -e "${BLU}Select environment :${RESET}"
        echo -e "${BLU}1. Development${RESET}"
        echo -e "${BLU}2. Test${RESET}"
        echo -e "${BLU}3. Production${RESET}"
        read ENVIRONMENT_SELECTION
    fi
	setEnvironment
}

setEnvironment()
{
	case $ENVIRONMENT_SELECTION in
		1)  ENVIRONMENT=dev
			;;
		2)  ENVIRONMENT=staging
			;;
        3)  ENVIRONMENT=prod
            ;;
		*) 	printf "\n${RED}No valid option selected${RESET}\n"
			selectEnvironment
			;;
	esac
}

# Function to securely input credentials
getCredentials() {
    while true; do
        read -r -p "Enter username [${DEFAULT_USERNAME}]: " INPUT_USER
        if [[ -z "$INPUT_USER" ]]; then
            USERNAME="$DEFAULT_USERNAME"
        else
            USERNAME="$INPUT_USER"
        fi

        read -s -r -p "Enter password: " PASSWORD
        echo
        if [[ -z "$PASSWORD" ]]; then
            echo "Error: Password cannot be empty."
            continue
        fi

        read -r -p "Enter service [${DEFAULT_AUTH_SERVICE_TEST}]: " INPUT_SERVICE
        if [[ -z "$INPUT_SERVICE" ]]; then
            AUTH_SERVICE_TEST="$DEFAULT_AUTH_SERVICE_TEST"
        else
            AUTH_SERVICE_TEST="$INPUT_SERVICE"
        fi

        export USERNAME PASSWORD AUTH_SERVICE_TEST
        break
    done
}
###### Function section - END