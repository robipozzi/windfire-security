source ../setenv.sh

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
    # 1) Root CA private key (encrypted)
    createRootCAPrivateKey
    # 2) Self-signed root CA certificate
    signRootCA
}

# ===== CREATE ROOT CA PRIVATE KEY FUNCTION =====
createRootCAPrivateKey()
{
    echo "Generating Root CA private key ..."
    openssl genrsa -aes256 -out rootCA.key 4096
    echo "Root CA private key generated"
}

# ===== SELF-SIGN ROOT CA CERTIFICATE FUNCTION =====
signRootCA()
{
    echo "Self signing Root CA certificate ..."
    openssl req -x509 -new -nodes -key rootCA.key -sha256 -days $DAYS_VALID \
            -out rootCA.crt \
            -subj "${SUBJECT}"
    echo "Root CA certificate self signed"
}

# ===== EXECUTION =====
main