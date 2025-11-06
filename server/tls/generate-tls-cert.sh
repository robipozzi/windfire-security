source ../../setenv.sh

# Configuration variables
COUNTRY=""
REGION=""
LOCALITY=""
ORGANIZATION=""
ORGANIZATIONAL_UNIT=""
COMMON_NAME=""
EMAIL=""
DAYS_VALID=365

# Generate self-signed certificate
generateCert()
{
    # Create the subject string
    #SUBJECT="/C=${COUNTRY}/ST=${REGION}/L=${LOCALITY}/O=${ORGANIZATION}/OU=${ORGANIZATIONAL_UNIT}/CN=${COMMON_NAME}/emailAddress=${EMAIL}"
    echo "Generating SSL certificate..."
    #echo "Subject: ${SUBJECT}"
    #openssl req -x509 -newkey rsa:4096 -nodes \
    #            -out windfire-security-cert.pem -subj "${SUBJECT}" \
    #            -keyout windfire-security-key.pem -days $DAYS_VALID
    openssl req -x509 -newkey rsa:4096 -nodes \
                -out windfire-security-cert.pem \
                -keyout windfire-security-key.pem -days $DAYS_VALID
    echo "SSL certificate generated"
}

# ***** MAIN EXECUTION
generateCert