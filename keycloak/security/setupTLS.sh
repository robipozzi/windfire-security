#!/bin/bash
source ../../common.sh

# ***** Setup Keycloak TLS with Windfire Keycloak Root CA
#
# Usage: ./setupTLS.sh [function] [environment]
#   function    : 1-4, as in the menu below (asked interactively if omitted)
#   environment : 1=Development, 2=Test, 3=Production (asked interactively if omitted)
#
# Every setting in the variable section can be overridden by an environment
# variable with the same name (e.g. RENEW_BEFORE_DAYS=60 ./setupTLS.sh 3 3).

# ===== VARIABLES =====
SCRIPT=setupTLS.sh
FUNCTION_CHOICE=$1
FUNCTION=
ENVIRONMENT_OPTION=$2
DEFAULT_OPENSSL=openssl
if command -v brew >/dev/null 2>&1 && [ -x "$(brew --prefix openssl@3 2>/dev/null)/bin/openssl" ]; then
    DEFAULT_OPENSSL="$(brew --prefix openssl@3)/bin/openssl"
fi
OPENSSL=${OPENSSL:-$DEFAULT_OPENSSL}
# Windfire Keycloak Root CA settings
CA_CN=${CA_CN:-"Windfire Keycloak Root CA"}
CA_ORG=${CA_ORG:-"Windfire"}
CA_DAYS=${CA_DAYS:-3650}
CA_KEY_BITS=${CA_KEY_BITS:-4096}
ROOT_CA_KEY_PATH=$KEYCLOAK_DEFAULT_KEYSTORE_DIR/$KEYCLOAK_ROOT_CA_KEY
ROOT_CA_CERTIFICATE_PATH=$KEYCLOAK_DEFAULT_TRUSTSTORE_DIR/$KEYCLOAK_ROOT_CA_CERTIFICATE
ROOT_CA_IN_PROGRESS=false
# Keycloak server certificate settings
SERVER_DAYS=${SERVER_DAYS:-397}
SERVER_KEY_BITS=${SERVER_KEY_BITS:-3072}
RENEW_BEFORE_DAYS=${RENEW_BEFORE_DAYS:-30}
KEYCLOAK_SERVER_KEY="$KEYCLOAK_CERT_NAME.key"
KEYCLOAK_SERVER_CERTIFICATE="$KEYCLOAK_CERT_NAME.crt"
KEYCLOAK_TLS_REMOTE_DIR=/etc/keycloak/tls
KEYCLOAK_CONF_REMOTE=/etc/keycloak/keycloak.conf
COMMON_NAME=
OPENSSL_CONFIG_FILE=
CERTS_DIR=
CSR_FILE=

# ===== MAIN FUNCTION =====
main()
{
    trap cleanup EXIT
    $FUNCTION
}

# ===== FUNCTION SELECTION FUNCTION =====
chooseFunction()
{
    if [ -z "$FUNCTION_CHOICE" ]; then
        echo -e "${GREEN}Choose function : ${RESET}"
        echo -e "${GREEN}1. Create Windfire Keycloak Root CA${RESET}"
        echo -e "${GREEN}2. Generate Keycloak server certificate signed by Windfire Keycloak Root CA${RESET}"
        echo -e "${GREEN}3. Check Windfire Keycloak Root CA and Keycloak server certificate${RESET}"
        echo -e "${GREEN}4. Generate all TLS configuration (1 + 2)${RESET}"
        read FUNCTION_CHOICE
    fi
    case $FUNCTION_CHOICE in
        1)  FUNCTION=createRootCA
            ;;
        2)  FUNCTION=generateServerCertificate
            ;;
        3)  FUNCTION=checkCertificates
            ;;
        4)  FUNCTION=createTLSConfiguration
            ;;
        *)  printf "\n${RED}No valid option selected${RESET}\n"
            FUNCTION_CHOICE=
            chooseFunction
            ;;
    esac
}

# ===== CREATE WINDFIRE KEYCLOAK ROOT CA FUNCTION =====
createRootCA()
{
    echo -e "${BLU}********************************************${RESET}"
    echo -e "${BLU}***** Create Windfire Keycloak Root CA *****${RESET}"
    echo -e "${BLU}********************************************${RESET}"
    echo

    checkOpenssl

    # Replacing a Root CA is a deliberate manual act: never overwrite an existing one
    if [ -f "$ROOT_CA_CERTIFICATE_PATH" ] || [ -f "$ROOT_CA_KEY_PATH" ] || [ -f "$ROOT_CA_KEY_PATH.sops.json" ]; then
        echo -e "${RED}Error: Windfire Keycloak Root CA already exists, refusing to overwrite it:${RESET}" >&2
        echo -e "${RED}  certificate : ${BLU}$ROOT_CA_CERTIFICATE_PATH${RESET}" >&2
        echo -e "${RED}  key         : ${BLU}$ROOT_CA_KEY_PATH${RESET}" >&2
        echo -e "${RED}Move the existing files away manually if you really want to create a new Root CA.${RESET}" >&2
        exit 1
    fi

    mkdir -p "$KEYCLOAK_DEFAULT_KEYSTORE_DIR" "$KEYCLOAK_DEFAULT_TRUSTSTORE_DIR" \
        || { echo -e "${RED}Error: failed to create directories $KEYCLOAK_DEFAULT_KEYSTORE_DIR and $KEYCLOAK_DEFAULT_TRUSTSTORE_DIR${RESET}" >&2; exit 1; }

    # From here on, partial files are removed by cleanup() if anything fails or the script is interrupted
    ROOT_CA_IN_PROGRESS=true

    # 1) Create Windfire Keycloak Root CA private key
    createRootCAPrivateKey

    # 2) Self-sign Windfire Keycloak Root CA certificate
    signRootCA

    ROOT_CA_IN_PROGRESS=false

    # 3) Print Root CA details and remind to protect the private key
    printRootCASummary
}

# ===== CREATE WINDFIRE KEYCLOAK ROOT CA PRIVATE KEY FUNCTION =====
createRootCAPrivateKey()
{
    echo -e "Generating Windfire Keycloak Root CA private key (RSA $CA_KEY_BITS, AES-256 encrypted) ..."
    echo -e "You will be asked for the Root CA private key passphrase"
    ( umask 077 && "$OPENSSL" genrsa -aes256 -out "$ROOT_CA_KEY_PATH" "$CA_KEY_BITS" ) \
        || { echo -e "${RED}Error: failed to generate Root CA private key${RESET}" >&2; exit 1; }
    chmod 600 "$ROOT_CA_KEY_PATH"
    echo -e "Windfire Keycloak Root CA private key ${BLU}$ROOT_CA_KEY_PATH${RESET} generated"
    echo
}

# ===== SELF-SIGN WINDFIRE KEYCLOAK ROOT CA CERTIFICATE FUNCTION =====
signRootCA()
{
    echo -e "Self signing Windfire Keycloak Root CA certificate (you will be asked for the Root CA private key passphrase) ..."
    "$OPENSSL" req -x509 -new -key "$ROOT_CA_KEY_PATH" -sha256 -days "$CA_DAYS" \
            -out "$ROOT_CA_CERTIFICATE_PATH" \
            -subj "/O=${CA_ORG}/CN=${CA_CN}" \
            -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
            -addext "keyUsage=critical,keyCertSign,cRLSign" \
            -addext "subjectKeyIdentifier=hash" \
        || { echo -e "${RED}Error: failed to self-sign Root CA certificate${RESET}" >&2; exit 1; }
    chmod 644 "$ROOT_CA_CERTIFICATE_PATH"
    echo -e "Windfire Keycloak Root CA certificate ${BLU}$ROOT_CA_CERTIFICATE_PATH${RESET} self signed"
    echo
}

# ===== PRINT WINDFIRE KEYCLOAK ROOT CA SUMMARY FUNCTION =====
printRootCASummary()
{
    echo -e "${BLU}***** Windfire Keycloak Root CA created *****${RESET}"
    echo -e "Certificate : ${BLU}$ROOT_CA_CERTIFICATE_PATH${RESET}"
    echo -e "Private key : ${BLU}$ROOT_CA_KEY_PATH${RESET}"
    "$OPENSSL" x509 -in "$ROOT_CA_CERTIFICATE_PATH" -noout -subject -enddate -fingerprint -sha256
    echo
    printDeleteRootCAKeyReminder
}

# ===== GENERATE KEYCLOAK SERVER CERTIFICATE FUNCTION =====
generateServerCertificate()
{
    echo -e "${BLU}************************************************************************************${RESET}"
    echo -e "${BLU}***** Generate Keycloak server certificate signed by Windfire Keycloak Root CA *****${RESET}"
    echo -e "${BLU}************************************************************************************${RESET}"
    echo

    checkOpenssl
    selectCertificateEnvironment
    checkRootCA

    mkdir -p "$CERTS_DIR" || { echo -e "${RED}Error: failed to create directory: $CERTS_DIR${RESET}" >&2; exit 1; }
    confirmOverwrite

    # 1) Create server private key
    createServerPrivateKey

    # 2) Create server CSR
    createServerCsr

    # 3) Sign server certificate with Windfire Keycloak Root CA
    signServerCertificate

    # 4) Verify server certificate chains to Windfire Keycloak Root CA
    verifyServerCertificate

    # 5) Print how to install the certificate on Keycloak server
    printInstallInstructions

    # 6) Remind to delete the Root CA private key, restored from the Password Manager for signing
    printDeleteRootCAKeyReminder
}

# ===== CREATE SERVER PRIVATE KEY FUNCTION =====
createServerPrivateKey()
{
    echo -e "Generating Keycloak server private key (RSA $SERVER_KEY_BITS) in $CERTS_DIR directory ..."
    ( umask 077 && "$OPENSSL" genrsa -out "$CERTS_DIR/$KEYCLOAK_SERVER_KEY" "$SERVER_KEY_BITS" ) \
        || { echo -e "${RED}Error: failed to generate server private key${RESET}" >&2; exit 1; }
    chmod 600 "$CERTS_DIR/$KEYCLOAK_SERVER_KEY"
    echo -e "Keycloak server private key ${BLU}$CERTS_DIR/$KEYCLOAK_SERVER_KEY${RESET} generated"
    echo
}

# ===== SERVER CSR CREATE FUNCTION =====
createServerCsr()
{
    echo "Creating Keycloak server CSR ..."
    CSR_FILE="$(mktemp)"
    "$OPENSSL" req -new -key "$CERTS_DIR/$KEYCLOAK_SERVER_KEY" -out "$CSR_FILE" -subj "/O=${CA_ORG}/CN=${COMMON_NAME}" \
        || { echo -e "${RED}Error: failed to create server CSR${RESET}" >&2; exit 1; }
    echo "Keycloak server CSR created"
    echo
}

# ===== SERVER CERTIFICATE SIGNING FUNCTION =====
signServerCertificate()
{
    # SANs and extensions come only from the openssl config file, never from the CSR.
    # A random serial is used, so no serial (.srl) file is kept next to the Root CA.
    echo "Signing Keycloak server certificate with Windfire Keycloak Root CA (you will be asked for the Root CA private key passphrase) ..."
    echo "  --> Using $OPENSSL_CONFIG_FILE openssl configuration file ..."
    if ! "$OPENSSL" x509 -req -in "$CSR_FILE" -CA "$ROOT_CA_CERTIFICATE_PATH" -CAkey "$ROOT_CA_KEY_PATH" \
                -set_serial "0x$("$OPENSSL" rand -hex 16)" \
                -out "$CERTS_DIR/$KEYCLOAK_SERVER_CERTIFICATE" -days "$SERVER_DAYS" -sha256 \
                -extfile "$OPENSSL_CONFIG_FILE"; then
        echo -e "${RED}Error: failed to sign server certificate${RESET}" >&2
        rm -f "$CERTS_DIR/$KEYCLOAK_SERVER_CERTIFICATE" "$CERTS_DIR/$KEYCLOAK_SERVER_KEY"
        exit 1
    fi
    chmod 644 "$CERTS_DIR/$KEYCLOAK_SERVER_CERTIFICATE"
    echo -e "Keycloak server certificate ${BLU}$CERTS_DIR/$KEYCLOAK_SERVER_CERTIFICATE${RESET} signed"
    echo
}

# ===== SERVER CERTIFICATE VERIFICATION FUNCTION =====
verifyServerCertificate()
{
    echo "Verifying Keycloak server certificate against Windfire Keycloak Root CA ..."
    "$OPENSSL" verify -CAfile "$ROOT_CA_CERTIFICATE_PATH" "$CERTS_DIR/$KEYCLOAK_SERVER_CERTIFICATE" \
        || { echo -e "${RED}Error: server certificate is not signed by Windfire Keycloak Root CA ${BLU}$ROOT_CA_CERTIFICATE_PATH${RESET}" >&2; exit 1; }

    CERT_PUBKEY=$("$OPENSSL" x509 -in "$CERTS_DIR/$KEYCLOAK_SERVER_CERTIFICATE" -noout -pubkey)
    KEY_PUBKEY=$("$OPENSSL" pkey -in "$CERTS_DIR/$KEYCLOAK_SERVER_KEY" -pubout)
    if [ "$CERT_PUBKEY" != "$KEY_PUBKEY" ]; then
        echo -e "${RED}Error: server certificate and private key do not match${RESET}" >&2
        exit 1
    fi

    "$OPENSSL" x509 -in "$CERTS_DIR/$KEYCLOAK_SERVER_CERTIFICATE" -noout -subject -issuer -ext subjectAltName,extendedKeyUsage -enddate
    echo -e "Keycloak server certificate ${BLU}$CERTS_DIR/$KEYCLOAK_SERVER_CERTIFICATE${RESET} verified"
    echo
}

# ===== PRINT INSTALL INSTRUCTIONS FUNCTION =====
printInstallInstructions()
{
    if [ "$ENVIRONMENT" != "prod" ]; then
        return
    fi
    echo -e "${BLU}***** Next steps on $COMMON_NAME *****${RESET}"
    echo -e "Copy the files to $COMMON_NAME and install them in ${BLU}$KEYCLOAK_TLS_REMOTE_DIR${RESET}:"
    echo "    scp \"$CERTS_DIR/$KEYCLOAK_SERVER_CERTIFICATE\" \"$CERTS_DIR/$KEYCLOAK_SERVER_KEY\" \"$ROOT_CA_CERTIFICATE_PATH\" pi@$COMMON_NAME:/tmp/"
    echo "    sudo install -o root -g keycloak -m 0640 /tmp/$KEYCLOAK_SERVER_CERTIFICATE /tmp/$KEYCLOAK_SERVER_KEY $KEYCLOAK_TLS_REMOTE_DIR/"
    echo "    sudo install -o root -g keycloak -m 0644 /tmp/$KEYCLOAK_ROOT_CA_CERTIFICATE $KEYCLOAK_TLS_REMOTE_DIR/"
    echo "    shred -u /tmp/$KEYCLOAK_SERVER_KEY && rm -f /tmp/$KEYCLOAK_SERVER_CERTIFICATE /tmp/$KEYCLOAK_ROOT_CA_CERTIFICATE"
    echo -e "and check that ${BLU}$KEYCLOAK_CONF_REMOTE${RESET} contains:"
    echo "    https-certificate-file=$KEYCLOAK_TLS_REMOTE_DIR/$KEYCLOAK_SERVER_CERTIFICATE"
    echo "    https-certificate-key-file=$KEYCLOAK_TLS_REMOTE_DIR/$KEYCLOAK_SERVER_KEY"
    echo -e "${YELLOW}Trust $KEYCLOAK_ROOT_CA_CERTIFICATE on every Keycloak client before restarting Keycloak.${RESET}"
    echo
}

# ===== CHECK CERTIFICATES FUNCTION =====
checkCertificates()
{
    echo -e "${BLU}***************************************************************************${RESET}"
    echo -e "${BLU}***** Check Windfire Keycloak Root CA and Keycloak server certificate *****${RESET}"
    echo -e "${BLU}***************************************************************************${RESET}"
    echo

    checkOpenssl
    selectCertificateEnvironment
    CHECK_FAILED=false

    if [ ! -f "$ROOT_CA_CERTIFICATE_PATH" ]; then
        echo -e "${RED}Error: Windfire Keycloak Root CA certificate not found: ${BLU}$ROOT_CA_CERTIFICATE_PATH${RESET}" >&2
        exit 1
    fi
    echo -e "Windfire Keycloak Root CA ${BLU}$ROOT_CA_CERTIFICATE_PATH${RESET}"
    "$OPENSSL" x509 -in "$ROOT_CA_CERTIFICATE_PATH" -noout -subject -issuer -enddate
    echo "Days left: $(daysLeft "$ROOT_CA_CERTIFICATE_PATH")"
    echo

    SERVER_CERTIFICATE_PATH=$CERTS_DIR/$KEYCLOAK_SERVER_CERTIFICATE
    if [ ! -f "$SERVER_CERTIFICATE_PATH" ]; then
        echo -e "${RED}Error: Keycloak server certificate not found: ${BLU}$SERVER_CERTIFICATE_PATH${RESET}" >&2
        exit 1
    fi
    echo -e "Keycloak server certificate ${BLU}$SERVER_CERTIFICATE_PATH${RESET}"
    "$OPENSSL" x509 -in "$SERVER_CERTIFICATE_PATH" -noout -subject -issuer -ext subjectAltName -enddate
    echo "Days left: $(daysLeft "$SERVER_CERTIFICATE_PATH")"
    echo

    if ! "$OPENSSL" verify -CAfile "$ROOT_CA_CERTIFICATE_PATH" "$SERVER_CERTIFICATE_PATH" >/dev/null 2>&1; then
        echo -e "${RED}FAILED: server certificate does not chain to Windfire Keycloak Root CA${RESET}"
        CHECK_FAILED=true
    else
        echo -e "${GREEN}OK: server certificate chains to Windfire Keycloak Root CA${RESET}"
    fi
    if ! "$OPENSSL" x509 -in "$SERVER_CERTIFICATE_PATH" -noout -checkend $((RENEW_BEFORE_DAYS * 86400)) >/dev/null; then
        echo -e "${RED}FAILED: server certificate expires within $RENEW_BEFORE_DAYS days, renew it with option 2${RESET}"
        CHECK_FAILED=true
    else
        echo -e "${GREEN}OK: server certificate does not expire within $RENEW_BEFORE_DAYS days${RESET}"
    fi
    echo

    if [ "$CHECK_FAILED" = true ]; then
        exit 1
    fi
}

# ===== GENERATE ALL TLS CONFIGURATION FUNCTION =====
createTLSConfiguration()
{
    createRootCA
    generateServerCertificate
}

# ===== HELPER FUNCTIONS =====
printDeleteRootCAKeyReminder()
{
    echo -e "${RED}*****************************************************************************${RESET}"
    echo -e "${RED}***** IMPORTANT: DELETE THE ROOT CA PRIVATE KEY FROM THE FILESYSTEM     *****${RESET}"
    echo -e "${RED}*****************************************************************************${RESET}"
    echo -e "${RED}The Windfire Keycloak Root CA private key is still on the filesystem:${RESET}"
    echo -e "    ${BLU}$ROOT_CA_KEY_PATH${RESET}"
    echo -e "${RED}It must NOT stay there: encrypt it, save it in the Password Manager, then delete it.${RESET}"
    echo "  Steps 1, 2 and 4 can be done in one go with the sops utility of this repository:"
    echo "       (cd ../../sops && ./encrypt-sops.sh 1 \"$ROOT_CA_KEY_PATH\")"
    echo "  or manually:"
    echo "  1) Encrypt it with sops/age (skip if the Password Manager already holds the current .sops.json):"
    echo "       sops -e --age \"\$(age-keygen -y ~/.config/sops/age/keys.txt)\" --input-type binary --output-type json \\"
    echo "            \"$ROOT_CA_KEY_PATH\" > \"$ROOT_CA_KEY_PATH.sops.json\""
    echo "  2) Check that it decrypts back to the same key:"
    echo "       sops -d --input-type json --output-type binary \"$ROOT_CA_KEY_PATH.sops.json\" | cmp - \"$ROOT_CA_KEY_PATH\""
    echo "  3) Save $KEYCLOAK_ROOT_CA_KEY.sops.json in the Password Manager"
    echo "  4) Delete the private key and the .sops.json from the filesystem:"
    echo "       rm -f \"$ROOT_CA_KEY_PATH\" \"$ROOT_CA_KEY_PATH.sops.json\""
    echo -e "${YELLOW}The key is needed again only to sign or renew a Keycloak server certificate: restore it from the${RESET}"
    echo -e "${YELLOW}Password Manager to the same path, run this script, then delete it again.${RESET}"
    echo
}

checkOpenssl()
{
    if ! command -v "$OPENSSL" >/dev/null 2>&1; then
        echo -e "${RED}Error: openssl not found: $OPENSSL (install it with: brew install openssl@3)${RESET}" >&2
        exit 1
    fi
    if "$OPENSSL" version | grep -q LibreSSL; then
        echo -e "${RED}Error: $OPENSSL is LibreSSL, OpenSSL 3 is required (brew install openssl@3)${RESET}" >&2
        exit 1
    fi
    echo -e "Using ${BOLD}$("$OPENSSL" version)${RESET} ($OPENSSL)"
    echo
}

checkRootCA()
{
    if [ ! -f "$ROOT_CA_CERTIFICATE_PATH" ] || [ ! -f "$ROOT_CA_KEY_PATH" ]; then
        echo -e "${RED}Error: Windfire Keycloak Root CA not found (expected ${BLU}$ROOT_CA_CERTIFICATE_PATH${RED} and ${BLU}$ROOT_CA_KEY_PATH${RED}).${RESET}" >&2
        echo -e "${RED}Run option 1 (Create Windfire Keycloak Root CA) first, or restore the decrypted key from the password manager.${RESET}" >&2
        exit 1
    fi
    echo -e "Using Windfire Keycloak Root CA ${BLU}$ROOT_CA_CERTIFICATE_PATH${RESET}"
    echo
}

selectCertificateEnvironment()
{
    if [ -n "$ENVIRONMENT_OPTION" ]; then
        ENVIRONMENT_SELECTION=$ENVIRONMENT_OPTION
        setEnvironment
    else
        selectEnvironment
    fi
    echo -e "Environment selected is ${BOLD}$ENVIRONMENT${RESET}"
    case "$ENVIRONMENT" in
        dev|staging)
            OPENSSL_CONFIG_FILE="openssl_config_localhost.ext"
            CERTS_DIR=$DEFAULT_TLS_DIR
            COMMON_NAME="localhost"
            ;;
        prod)
            OPENSSL_CONFIG_FILE="openssl_config_raspberry.ext"
            CERTS_DIR=$KEYCLOAK_DEFAULT_CERTS_PROD_DIR
            COMMON_NAME="raspberry01"
            ;;
        *)
            echo -e "${RED}Error: Invalid environment '$ENVIRONMENT'${RESET}"
            echo "Valid options: dev, staging, prod"
            exit 1
            ;;
    esac
    echo -e "Openssl config file set to ${BOLD}$OPENSSL_CONFIG_FILE${RESET}, certificates directory set to ${BOLD}$CERTS_DIR${RESET}"
    echo
}

confirmOverwrite()
{
    if [ -f "$CERTS_DIR/$KEYCLOAK_SERVER_CERTIFICATE" ] || [ -f "$CERTS_DIR/$KEYCLOAK_SERVER_KEY" ]; then
        echo -e "${YELLOW}Keycloak server certificate/key already exist in ${BLU}$CERTS_DIR${RESET}"
        read -r -p "Overwrite them? [y/N]: " OVERWRITE
        if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
            echo "Nothing changed"
            exit 0
        fi
    fi
}

daysLeft()
{
    END_DATE=$("$OPENSSL" x509 -in "$1" -noout -enddate | cut -d= -f2)
    if date -j >/dev/null 2>&1; then
        END_EPOCH=$(date -j -f "%b %e %T %Y %Z" "$END_DATE" +%s)
    else
        END_EPOCH=$(date -d "$END_DATE" +%s)
    fi
    echo $(( (END_EPOCH - $(date +%s)) / 86400 ))
}

cleanup()
{
    if [ -n "$CSR_FILE" ]; then
        rm -f "$CSR_FILE"
    fi
    # Remove a partially created Root CA, so that a new run is not refused
    if [ "$ROOT_CA_IN_PROGRESS" = true ]; then
        echo -e "${RED}Root CA creation did not complete, removing partial files${RESET}" >&2
        rm -f "$ROOT_CA_KEY_PATH" "$ROOT_CA_CERTIFICATE_PATH"
    fi
}

# ##############################################
# #################### MAIN ####################
# ##############################################
chooseFunction
main
