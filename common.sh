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
# ===== DEPLOYMENT / UNDEPLOYMENT VARIABLES =====
PLATFORM_OPTION=$1
PLATFORM_SELECTED=false
DEPLOY_PLATFORM=
DEPLOY_FUNCTION=

# ===== PYTHON VIRTUAL ENVIRONMENTS VARIABLES =====
PYTHON_SERVER_VIRTUAL_ENV=windfire-security-server
PYTHON_TEST_VIRTUAL_ENV=windfire-security-test
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
KEYCLOAK_CONF_TLS_DIR=$KEYCLOAK_HOME/conf/tls

# ===== KEYCLOAK ROOT CA VARIABLES =====
KEYCLOAK_ROOT_CA_KEY="WindfireKeycloakRootCA.key"
KEYCLOAK_ROOT_CA_CERTIFICATE="WindfireKeycloakRootCA.crt"
KEYCLOAK_DEFAULT_KEYSTORE_DIR=$HOME/opt/keycloak/ssl/keystore
KEYCLOAK_DEFAULT_TRUSTSTORE_DIR=$HOME/opt/keycloak/ssl/truststore
KEYCLOAK_DEFAULT_CERTS_PROD_DIR=$HOME/opt/keycloak/ssl/certs/raspberry

# ===== KEYCLOAK SERVER CERTIFICATE VARIABLES =====
KEYCLOAK_CERT_NAME="windfire-keycloak"

# ===== SOPS VARIABLES =====
DEFAULT_SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt
SOPS_ENCRYPTED_SUFFIX=".sops.json"
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

# Functions to select and set deployment platform
selectDeploymentPlatform()
{
    if [[ $PLATFORM_OPTION == "" && $PLATFORM_SELECTED == false ]]; then
        echo -e "${BLU}No platform option provided - Select deployment platform :${RESET}"
        echo -e "${GREEN}1. Raspberry${RESET}"
        read PLATFORM_OPTION
        setDeploymentPlatform
    else
        echo -e "${CYAN}Platform option provided as argument: $PLATFORM_OPTION${RESET}"
        setDeploymentPlatform
    fi
}

setDeploymentPlatform()
{
    case $PLATFORM_OPTION in
        1)  DEPLOY_PLATFORM="raspberry"
            PLATFORM_SELECTED=true
            DEPLOY_PLATFORM="raspberry"
            ;;
        *)  echo -e "${RED}No valid option selected${RESET}"
            PLATFORM_OPTION=""
            PLATFORM_SELECTED=false
            selectDeploymentPlatform
            ;;
    esac
}
###### Function section - END