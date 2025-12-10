source ../setenv.sh
source ../commons.sh

# ===== VARIABLES =====
COUNTRY="IT"
REGION="Lombardia"
LOCALITY="Milano"
ORGANIZATION="Windfire"
ORGANIZATIONAL_UNIT="Windfire Security"
COMMON_NAME=""
EMAIL="r.robipozzi@gmail.com"
DAYS_VALID=365
SUBJECT=""
SERVER_PRIVATE_KEY="windfire-security.key"
SERVER_CSR="windfire-security.csr"
OPENSSL_CONFIG_FILE=""

# ===== MAIN FUNCTION =====
main()
{
    # Select environment for 
    printSelectEnvironment
    echo -e "Environment selected is ${BOLD}$ENVIRONMENT${RESET}"
    case "$ENVIRONMENT" in
        dev|staging)
            OPENSSL_CONFIG_FILE="openssl_config_localhost.ext"
            ;;
        prod)
            OPENSSL_CONFIG_FILE="openssl_config_raspberry.ext"
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
}

# ===== CREATE SERVER PRIVATE KEY FUNCTION =====
createServerPrivateKey()
{
    echo "Generating server private key ..."
    openssl genrsa -out ../server/ssl/$SERVER_PRIVATE_KEY 2048
    echo "Server private key generated"
}

# ===== SERVER CSR CREATE FUNCTION =====
createServerCsr()
{
    echo "Creating Server CSR ..."
    openssl req -new -key ../server/ssl/$SERVER_PRIVATE_KEY -out $SERVER_CSR -subj "${SUBJECT}"
    echo "Server CSR created"
}

# ===== SERVER CERTIFICATE SIGNING FUNCTION =====
signServerCertificate()
{
    echo "Signing Server Certificate ..."
    openssl x509 -req -in $SERVER_CSR -CA $WINDFIRE_ROOT_CA_CERTIFICATE -CAkey $WINDFIRE_ROOT_CA_KEY -CAcreateserial \
                -out ../server/ssl/windfire-security.crt -days $DAYS_VALID -sha256 \
                -extfile openssl_config_localhost.ext
    echo "Server Certificate signed"
}

getCN() {
    while true; do
        read -r -p "Enter server Common Name (CN) [e.g.: localhost]: " CN
        if [[ -z "$CN" ]]; then
            echo -e "${RED}Error: Common Name (CN) cannot be empty${RESET}"
            continue
        fi
        COMMON_NAME=$CN
        break
    done
}

# ===== EXECUTION =====
main