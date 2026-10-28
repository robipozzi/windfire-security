#!/bin/bash
source ../common.sh

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

    # 4) Copy Windfire root CA key to Windfire keystore
    copyRootCAKeyToKeystore

    # 5) Delete Windfire root CA certificate and key from ssl folder
    deleteRootCAFromSslFolder
}

# ===== CREATE WINDFIRE ROOT CA PRIVATE KEY FUNCTION =====
createRootCAPrivateKey()
{
    echo -e "Generating Windfire Root CA private key ..."
    openssl genrsa -aes256 -out $WINDFIRE_ROOT_CA_KEY 4096 || { echo -e "${RED}Error: failed to generate Root CA private key${RESET}" >&2; exit 1; }
    echo -e "Windfire Root CA private key ${BLU}$WINDFIRE_ROOT_CA_KEY${RESET} generated"
    echo
}

# ===== SELF-SIGN WINDFIRE ROOT CA CERTIFICATE FUNCTION =====
signRootCA()
{
    echo -e "Self signing Windfire Root CA certificate ..."
    openssl req -x509 -new -nodes -key $WINDFIRE_ROOT_CA_KEY -sha256 -days $DAYS_VALID \
            -out $WINDFIRE_ROOT_CA_CERTIFICATE \
            -subj "${SUBJECT}" \
            -addext "keyUsage=critical,keyCertSign,cRLSign" \
            -addext "basicConstraints=critical,CA:true" \
            -addext "subjectKeyIdentifier=hash" \
        || { echo -e "${RED}Error: failed to self-sign Root CA certificate${RESET}" >&2; rm -f "$WINDFIRE_ROOT_CA_CERTIFICATE"; exit 1; }
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

# ===== DELETE WINDFIRE ROOT CA CERTIFICATE AND KEY FROM SSL FOLDER FUNCTION =====
deleteRootCAFromSslFolder()
{
    echo -e "Deleting Windfire Root CA certificate and key from ssl folder ..."

    # Only delete if both copies (truststore certificate and keystore key) succeeded
    if [ ! -f "$WINDFIRE_DEFAULT_TRUSTSTORE_DIR/$WINDFIRE_ROOT_CA_CERTIFICATE" ]; then
        echo -e "${RED}Error: certificate not found in truststore, skipping cleanup: $WINDFIRE_DEFAULT_TRUSTSTORE_DIR/$WINDFIRE_ROOT_CA_CERTIFICATE${RESET}" >&2
        exit 1
    fi
    if [ ! -f "$WINDFIRE_DEFAULT_KEYSTORE_DIR/$WINDFIRE_ROOT_CA_KEY" ]; then
        echo -e "${RED}Error: key not found in keystore, skipping cleanup: $WINDFIRE_DEFAULT_KEYSTORE_DIR/$WINDFIRE_ROOT_CA_KEY${RESET}" >&2
        exit 1
    fi

    rm -f "$WINDFIRE_ROOT_CA_CERTIFICATE" "$WINDFIRE_ROOT_CA_KEY" || { echo -e "${RED}Error: failed to delete Root CA certificate/key from ssl folder${RESET}" >&2; exit 1; }
    echo -e "Windfire Root CA certificate ${BLU}$WINDFIRE_ROOT_CA_CERTIFICATE${RESET} and key ${BLU}$WINDFIRE_ROOT_CA_KEY${RESET} deleted from ssl folder"
    echo
}

# ===== EXECUTION =====
main