#!/bin/bash
source ../setenv.sh

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
    printSelectEnvironment
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
    openssl genrsa -out $CERTS_DIR/$WINDFIRE_SECURITY_PRIVATE_KEY 2048
    echo "Server private key generated"
    echo 
}

# ===== SERVER CSR CREATE FUNCTION =====
createServerCsr()
{
    echo "Creating Server CSR ..."
    openssl req -new -key $CERTS_DIR/$WINDFIRE_SECURITY_PRIVATE_KEY -out $WINDFIRE_SECURITY_CSR -subj "${SUBJECT}"
    echo "Server CSR created"
    echo 
}

# ===== SERVER CERTIFICATE SIGNING FUNCTION =====
signServerCertificate()
{
    echo "Signing Server Certificate ..."
    echo "  --> Create Server Certificate in $CERTS_DIR directory ..."
    echo "  --> Using $OPENSSL_CONFIG_FILE openssl configuration file ..."
    openssl x509 -req -in $WINDFIRE_SECURITY_CSR -CA $WINDFIRE_ROOT_CA_CERTIFICATE -CAkey $WINDFIRE_ROOT_CA_KEY -CAcreateserial \
                -out $CERTS_DIR/$WINDFIRE_SECURITY_CERTIFICATE -days $DAYS_VALID -sha256 \
                -extfile $OPENSSL_CONFIG_FILE
    echo "Server Certificate signed"
    echo 
}

# ===== SERVER CSR DELETE FUNCTION =====
deleteServerCsr()
{
    echo "Deleting Server CSR ..."
    rm $WINDFIRE_SECURITY_CSR
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