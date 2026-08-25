#!/bin/bash
source ../common.sh

# ***** Generate Windfire Security Server Certificate

# ===== VARIABLES =====
COUNTRY="IT"
REGION="Lombardia"
LOCALITY="Milano"
ORGANIZATION="Windfire"
ORGANIZATIONAL_UNIT="Windfire Security"
COMMON_NAME="Windfire Security Server"
EMAIL="r.robipozzi@gmail.com"
DAYS_VALID=365
SUBJECT=""
WINDFIRE_SECURITY_PRIVATE_KEY="windfire-security.key"
WINDFIRE_SECURITY_CERTIFICATE="windfire-security.crt"
WINDFIRE_SECURITY_CSR="windfire-security.csr"
OPENSSL_CONFIG_FILE=""

# ===== MAIN FUNCTION =====
main()
{
    # Select environment
    selectEnvironment
    echo -e "Environment selected is ${BOLD}$ENVIRONMENT${RESET}"
    case "$ENVIRONMENT" in
        dev|staging)
            OPENSSL_CONFIG_FILE="openssl_config_localhost.ext"
            CERTS_DIR="../server/ssl"
            ;;
        prod)
            OPENSSL_CONFIG_FILE="openssl_config_raspberry.ext"
            CERTS_DIR=$WINDFIRE_DEFAULT_CERTS_PROD_DIR
            # Check if Certs directory exists, in case it does not exist, create it
            if [ ! -d "$CERTS_DIR" ]; then
                mkdir -p "$CERTS_DIR" || { echo -e "${RED}Error: failed to create directory: $CERTS_DIR${RED}" >&2; exit 1; }
            fi
            ;;
        *)
            echo -e "${RED}Error: Invalid environment '$ENVIRONMENT'${RESET}"
            echo "Valid options: dev, staging, prod"
            exit 1
            ;;
    esac
    echo -e "Openssl config file set to ${BOLD}$OPENSSL_CONFIG_FILE${RESET}"

    # Enter server Common Name (CN) [e.g.: localhost]
    getCN
    SUBJECT="/C=${COUNTRY}/ST=${REGION}/L=${LOCALITY}/O=${ORGANIZATION}/OU=${ORGANIZATIONAL_UNIT}/CN=${COMMON_NAME}/emailAddress=${EMAIL}"
    echo "Subject: ${SUBJECT}"
    
    # 1) Create server private key
    createServerPrivateKey
    
    # 2) Create server CSR (Common Name must match host, or use SANs)
    createServerCsr
    
    # 3) Sign server certificate
    signServerCertificate

    # 4) Delete server CSR
    deleteServerCsr
}

# ===== CREATE SERVER PRIVATE KEY FUNCTION =====
createServerPrivateKey()
{
    echo "Generating server private key in $CERTS_DIR directory ..."
    openssl genrsa -out $CERTS_DIR/$WINDFIRE_SECURITY_PRIVATE_KEY 2048 \
        || { echo -e "${RED}Error: failed to generate server private key${RESET}" >&2; exit 1; }
    echo "Server private key generated"
    echo
}

# ===== SERVER CSR CREATE FUNCTION =====
createServerCsr()
{
    echo "Creating Server CSR ..."
    openssl req -new -key $CERTS_DIR/$WINDFIRE_SECURITY_PRIVATE_KEY -out $WINDFIRE_SECURITY_CSR -subj "${SUBJECT}" \
        || { echo -e "${RED}Error: failed to create server CSR${RESET}" >&2; exit 1; }
    echo "Server CSR created"
    echo
}

# ===== SERVER CERTIFICATE SIGNING FUNCTION =====
signServerCertificate()
{
    # Root CA cert/key are only guaranteed to persist where createRootCA.sh
    # copies them (keystore/truststore), not as leftover files in the CWD.
    ROOT_CA_CERTIFICATE_PATH="$WINDFIRE_DEFAULT_TRUSTSTORE_DIR/$WINDFIRE_ROOT_CA_CERTIFICATE"
    ROOT_CA_KEY_PATH="$WINDFIRE_DEFAULT_KEYSTORE_DIR/$WINDFIRE_ROOT_CA_KEY"

    if [ ! -f "$ROOT_CA_CERTIFICATE_PATH" ] || [ ! -f "$ROOT_CA_KEY_PATH" ]; then
        echo -e "${RED}Error: Windfire Root CA not found (expected ${BLU}$ROOT_CA_CERTIFICATE_PATH${RED} and ${BLU}$ROOT_CA_KEY_PATH${RED}).${RESET}" >&2
        echo -e "${RED}Run createRootCA.sh first.${RESET}" >&2
        exit 1
    fi

    echo "Signing Server Certificate ..."
    echo "  --> Create Server Certificate in $CERTS_DIR directory ..."
    echo "  --> Using $OPENSSL_CONFIG_FILE openssl configuration file ..."
    if ! openssl x509 -req -in $WINDFIRE_SECURITY_CSR -CA "$ROOT_CA_CERTIFICATE_PATH" -CAkey "$ROOT_CA_KEY_PATH" -CAcreateserial \
                -out $CERTS_DIR/$WINDFIRE_SECURITY_CERTIFICATE -days $DAYS_VALID -sha256 \
                -extfile $OPENSSL_CONFIG_FILE; then
        echo -e "${RED}Error: failed to sign server certificate${RESET}" >&2
        rm -f "$CERTS_DIR/$WINDFIRE_SECURITY_CERTIFICATE"
        exit 1
    fi
    echo "Server Certificate signed"
    echo
}

# ===== SERVER CSR DELETE FUNCTION =====
deleteServerCsr()
{
    echo "Deleting Server CSR ..."
    rm -f $WINDFIRE_SECURITY_CSR
    echo "Server CSR deleted"
    echo
}

# ===== SERVER COMMON NAME SETTING FUNCTION =====
getCN() {
    while true; do
        read -r -p "Enter server Common Name (CN) [$COMMON_NAME]: " CN
        if [[ -z "$CN" ]]; then
            echo -e "${BOLD}Common Name (CN) not input, going with default ${BLU}$COMMON_NAME${RESET}${RESET}"
            break
        fi
        COMMON_NAME=$CN
        break
    done
}

# ===== EXECUTION =====
main