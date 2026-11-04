##### TERMINAL COLORS - START
# ===== COLOR CODES =====
GREEN=$'\e[0;32m'
YELLOW=$'\e[1;33m'
RED=$'\e[1;31m'
MAGENTA=$'\e[1;35m'
BLU=$'\e[1;34m'
CYAN=$'\e[1;36m'
RESET=$'\e[0m'
END=$'\e[0m'
BOLD=$'\e[1m'
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
# Repository root (resolved from this file, so it works whatever the caller's working directory is)
WINDFIRE_SECURITY_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINDFIRE_SERVER_CERTIFICATE=windfire-security.crt
WINDFIRE_SERVER_KEY=windfire-security.key
ANSIBLE_SSH_KEY=$HOME/.ssh/ansible_rsa

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

# ===== PRIVATE CA NAME CONSTRAINTS VARIABLES =====
# The only names the Windfire Root CA and the Windfire Keycloak Root CA may issue certificates for
# (critical nameConstraints extension). Space-separated openssl GeneralNames: to add a host, add it
# here, then recreate both Root CAs and reissue their server certificates.
WINDFIRE_CA_PERMITTED_NAMES="DNS:raspberry01 DNS:raspberry02 DNS:localhost IP:127.0.0.1/255.255.255.255"
NAME_CONSTRAINTS_TEST_DIR=

# ===== KEYCLOAK SETTINGS VARIABLES =====
# Single source of the local Keycloak version: install-keycloak.sh (localhost), start-keycloak.sh and Docker
KEYCLOAK_VERSION=26.8.1
KEYCLOAK_HOME=$HOME/software/keycloak-$KEYCLOAK_VERSION
KEYCLOAK_DOCKER_IMAGE=quay.io/keycloak/keycloak
KEYCLOAK_DOCKER_IMAGE_VERSION=$KEYCLOAK_VERSION
KEYCLOAK_MIN_JAVA_VERSION=17
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

# Function to read a single KEY=value from an env file (.env can't be sourced: values with spaces, inline comments)
getEnvFileValue()
{
    local file=$1
    local key=$2
    local value
    value=$(grep -E "^${key}=" "$file" 2>/dev/null | tail -n 1)
    value=${value#*=}
    value=${value%%#*}
    value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    value=${value#[\"\']}
    value=${value%[\"\']}
    echo "$value"
}

# Function to build the openssl nameConstraints extension value from WINDFIRE_CA_PERMITTED_NAMES
buildNameConstraints()
{
    local name
    local value="critical"
    if [[ -z "${WINDFIRE_CA_PERMITTED_NAMES// /}" ]]; then
        echo -e "${RED}Error: WINDFIRE_CA_PERMITTED_NAMES in common.sh is empty${RESET}" >&2
        return 1
    fi
    for name in $WINDFIRE_CA_PERMITTED_NAMES; do
        value="${value},permitted;${name}"
    done
    echo "$value"
}

# Function to print the names a Root CA is going to be restricted to
printPermittedNames()
{
    local name
    echo -e "The Root CA will be restricted (critical nameConstraints) to these names, from ${BOLD}WINDFIRE_CA_PERMITTED_NAMES${RESET} in common.sh:"
    for name in $WINDFIRE_CA_PERMITTED_NAMES; do
        echo -e "    ${BLU}${name}${RESET}"
    done
}

# Function to check that a CA certificate carries the critical nameConstraints extension with every permitted name
# Usage: verifyNameConstraints <openssl binary> <CA certificate>
verifyNameConstraints()
{
    local openssl_bin=$1
    local cert=$2
    local ext
    local name
    ext=$("$openssl_bin" x509 -in "$cert" -noout -ext nameConstraints 2>/dev/null)
    if ! grep -q "Name Constraints: critical" <<< "$ext" || ! grep -q "Permitted:" <<< "$ext"; then
        echo -e "${RED}Error: critical nameConstraints extension not found in ${BLU}$cert${RESET}" >&2
        return 1
    fi
    for name in $WINDFIRE_CA_PERMITTED_NAMES; do
        if ! grep -qF "$name" <<< "$ext"; then
            echo -e "${RED}Error: permitted name ${BLU}$name${RED} missing from the nameConstraints extension of ${BLU}$cert${RESET}" >&2
            return 1
        fi
    done
    echo "$ext"
    echo -e "${GREEN}OK: nameConstraints extension present in $cert${RESET}"
}

# Function to check that a CA refuses a name outside WINDFIRE_CA_PERMITTED_NAMES: issues a throwaway certificate
# for example.com, checks that openssl verify rejects it with a name constraints violation, then deletes it.
# The caller's EXIT trap must remove NAME_CONSTRAINTS_TEST_DIR, in case the script is interrupted.
# Usage: testNameConstraints <openssl binary> <CA certificate> <CA private key>
testNameConstraints()
{
    local openssl_bin=$1
    local ca_cert=$2
    local ca_key=$3
    local verify_output
    local verify_rc
    NAME_CONSTRAINTS_TEST_DIR=$(mktemp -d) || { echo -e "${RED}Error: failed to create a temporary directory${RESET}" >&2; return 1; }
    printf '%s\n' "basicConstraints = critical, CA:FALSE" \
                  "keyUsage = critical, digitalSignature, keyEncipherment" \
                  "extendedKeyUsage = serverAuth" \
                  "subjectAltName = DNS:example.com" > "$NAME_CONSTRAINTS_TEST_DIR/example.ext"

    echo "Issuing a throwaway certificate for example.com (you will be asked for the Root CA private key passphrase) ..."
    if ! "$openssl_bin" req -new -newkey rsa:2048 -nodes -subj "/CN=example.com" \
                -keyout "$NAME_CONSTRAINTS_TEST_DIR/example.key" -out "$NAME_CONSTRAINTS_TEST_DIR/example.csr" 2>/dev/null \
       || ! "$openssl_bin" x509 -req -in "$NAME_CONSTRAINTS_TEST_DIR/example.csr" -CA "$ca_cert" -CAkey "$ca_key" \
                -set_serial "0x$("$openssl_bin" rand -hex 16)" -days 1 -sha256 \
                -extfile "$NAME_CONSTRAINTS_TEST_DIR/example.ext" -out "$NAME_CONSTRAINTS_TEST_DIR/example.crt"; then
        echo -e "${RED}Error: failed to issue the throwaway example.com certificate${RESET}" >&2
        rm -rf "$NAME_CONSTRAINTS_TEST_DIR"
        NAME_CONSTRAINTS_TEST_DIR=
        return 1
    fi

    echo "Verifying the example.com certificate against $ca_cert (it must be rejected) ..."
    verify_output=$("$openssl_bin" verify -CAfile "$ca_cert" "$NAME_CONSTRAINTS_TEST_DIR/example.crt" 2>&1)
    verify_rc=$?
    rm -rf "$NAME_CONSTRAINTS_TEST_DIR"
    NAME_CONSTRAINTS_TEST_DIR=
    echo "$verify_output"
    echo "Throwaway example.com certificate and key deleted"
    if [[ $verify_rc -ne 0 ]] && grep -qiE "permitted subtree violation|name constraint" <<< "$verify_output"; then
        echo -e "${GREEN}PASS: the Root CA rejects example.com with a name constraints violation${RESET}"
        return 0
    fi
    echo -e "${RED}FAIL: example.com was not rejected with a name constraints violation, the Root CA is not restricted${RESET}" >&2
    return 1
}

# Function to print how to trust a Root CA on this Mac (login keychain only) and retire the previous, unconstrained one
# Usage: printKeychainTrustInstructions <openssl binary> <CA certificate> <CA common name>
printKeychainTrustInstructions()
{
    local openssl_bin=$1
    local cert=$2
    local cn=$3
    local new_sha1
    new_sha1=$("$openssl_bin" x509 -in "$cert" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)
    echo -e "${BLU}***** Trust $cn on this Mac (login keychain: current user only, no sudo) *****${RESET}"
    echo "  1) Retire the previous, unconstrained $cn, otherwise the name constraints protect nothing."
    echo "     Old and new have the same name, so list them by SHA-1 fingerprint:"
    echo "       security find-certificate -a -c \"$cn\" -Z ~/Library/Keychains/login.keychain-db | grep SHA-1"
    echo "       security find-certificate -a -c \"$cn\" -Z /Library/Keychains/System.keychain | grep SHA-1"
    echo "     The new certificate is SHA-1 $new_sha1: delete every other one with"
    echo "       security delete-certificate -Z <old SHA-1> ~/Library/Keychains/login.keychain-db"
    echo "       sudo security delete-certificate -Z <old SHA-1> /Library/Keychains/System.keychain"
    echo "  2) Trust the new one in the login keychain, never the System keychain (macOS asks for your password):"
    echo "       security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db \"$cert\""
    echo
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

# Function to check that Java $KEYCLOAK_MIN_JAVA_VERSION or later is available to run Keycloak
checkJava()
{
    local java_bin=java
    local java_major
    if [[ -n "$JAVA_HOME" ]]; then
        java_bin="$JAVA_HOME/bin/java"
    fi
    java_major=$("$java_bin" -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -n 1)
    if [[ -z "$java_major" || "$java_major" -lt $KEYCLOAK_MIN_JAVA_VERSION ]]; then
        echo -e "${RED}Keycloak needs Java $KEYCLOAK_MIN_JAVA_VERSION or later, found: ${java_major:-none} (install it e.g. with brew install openjdk@21)${RESET}" >&2
        return 1
    fi
}

# Functions to select and set deployment platform
selectDeploymentPlatform()
{
    if [[ $PLATFORM_OPTION == "" && $PLATFORM_SELECTED == false ]]; then
        echo -e "${BLU}No platform option provided - Select deployment platform :${RESET}"
        echo -e "${GREEN}1. Raspberry${RESET}"
        if ! read PLATFORM_OPTION; then
            echo -e "${RED}No input available to select deployment platform${RESET}"
            exit 1
        fi
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