#!/bin/bash
source ../setenv.sh

# ***** Create Windfire Root CA

# ===== VARIABLES =====
COUNTRY="IT"
REGION="Lombardia"
LOCALITY="Milano"
ORGANIZATION="Windfire"
ORGANIZATIONAL_UNIT="Root CA"
COMMON_NAME="Windfire Root CA"
EMAIL="r.robipozzi@gmail.com"
DAYS_VALID=365
SUBJECT=""

# ===== MAIN FUNCTION =====
main()
{
    SUBJECT="/C=${COUNTRY}/ST=${REGION}/L=${LOCALITY}/O=${ORGANIZATION}/OU=${ORGANIZATIONAL_UNIT}/CN=${COMMON_NAME}/emailAddress=${EMAIL}"
    echo "Subject: ${SUBJECT}"
    
    # 1) Create Windfire Root CA private key
    createRootCAPrivateKey
    
    # 2) Self-sign Windfire root CA certificate
    signRootCA
    
    # 3) Copy Windfire root CA certificate to Windfire truststore
    copyRootCAToTruststore
    
    # 3) Copy Windfire root CA key to Windfire keystore
    copyRootCAKeyToKeystore
}

# ===== CREATE WINDFIRE ROOT CA PRIVATE KEY FUNCTION =====
createRootCAPrivateKey()
{
    echo -e "Generating Windfire Root CA private key ..."
    openssl genrsa -aes256 -out $WINDFIRE_ROOT_CA_KEY 4096
    echo -e "Windfire Root CA private key ${BLU}$WINDFIRE_ROOT_CA_KEY${RESET} generated"
    echo 
}

# ===== SELF-SIGN WINDFIRE ROOT CA CERTIFICATE FUNCTION =====
signRootCA()
{
    echo -e "Self signing Windfire Root CA certificate ..."
    openssl req -x509 -new -nodes -key $WINDFIRE_ROOT_CA_KEY -sha256 -days $DAYS_VALID \
            -out $WINDFIRE_ROOT_CA_CERTIFICATE \
            -subj "${SUBJECT}"
    echo -e "Windfire Root CA certificate ${BLU}$WINDFIRE_ROOT_CA_CERTIFICATE${RESET} self signed"
    echo 
}

# ===== COPY WINDFIRE ROOT CA CERTIFICATE TO TRUSTSTORE FUNCTION =====
copyRootCAToTruststore()
{
    echo -e "Copying Windfire Root CA certificate to truststore ..."
    
    # Check if Truststore directory exists, in case it does not exist, create it
    if [ ! -d "$WINDFIRE_DEFAULT_TRUSTSTORE_DIR" ]; then
        mkdir -p "$WINDFIRE_DEFAULT_TRUSTSTORE_DIR" || { echo -e "${RED}Error: failed to create directory: $WINDFIRE_DEFAULT_TRUSTSTORE_DIR${RESET}" >&2; exit 1; }
    fi

    # Check if Root CA certificate exists
    if [ ! -f "$WINDFIRE_ROOT_CA_CERTIFICATE" ]; then
        echo -e "${RED}Error: certificate not found: $WINDFIRE_ROOT_CA_CERTIFICATE${RESET}" >&2
        exit 1
    fi

    # Copy Root CA certificate to Truststore directory
    cp -f "$WINDFIRE_ROOT_CA_CERTIFICATE" "$WINDFIRE_DEFAULT_TRUSTSTORE_DIR/"
    echo -e "Windfire Root CA certificate ${BLU}$WINDFIRE_ROOT_CA_CERTIFICATE${RESET} copied to truststore ${BLU}$WINDFIRE_DEFAULT_TRUSTSTORE_DIR${RESET}"
    echo 
}

# ===== COPY WINDFIRE ROOT CA KEY TO KEYSTORE FUNCTION =====
copyRootCAKeyToKeystore()
{
    echo -e "Copying Windfire Root CA key to keystore ..."

    # Check if Keystore directory exists, in case it does not exist, create it
    if [ ! -d "$WINDFIRE_DEFAULT_KEYSTORE_DIR" ]; then
        mkdir -p "$WINDFIRE_DEFAULT_KEYSTORE_DIR" || { echo -e "${RED}Error: failed to create directory: $WINDFIRE_DEFAULT_KEYSTORE_DIR${RESET}" >&2; exit 1; }
    fi

    # Check if Root CA key exists
    if [ ! -f "$WINDFIRE_ROOT_CA_KEY" ]; then
        echo -e "${RED}Error: key not found: $WINDFIRE_ROOT_CA_KEY${RESET}" >&2
        exit 1
    fi

    # Copy Root CA key to Keystore directory
    cp -f "$WINDFIRE_ROOT_CA_KEY" "$WINDFIRE_DEFAULT_KEYSTORE_DIR/"
    echo -e "Windfire Root CA key ${BLU}$WINDFIRE_ROOT_CA_KEY${RESET} copied to keystore ${BLU}$WINDFIRE_DEFAULT_KEYSTORE_DIR${RESET}"
    echo 
}

# ===== EXECUTION =====
main