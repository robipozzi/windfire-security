source ../../common.sh

# ##### Variable section - START
SCRIPT=setupTLS.sh
FUNCTION_CHOICE=
FUNCTION=
KEYSTORE=$1
VALIDITY=$2
TRUSTSTORE=$3
# ##### Variable section - END

# ***** Function section - START
main()
{
    mkdir -p $DEFAULT_TLS_DIR
    $FUNCTION
}

chooseFunction()
{
	echo ${GREEN}Choose function : ${RESET}
    echo "${GREEN}1. Create our own Certification Authority${RESET}"
    echo "${GREEN}2. Generate server keystore and certificate signing request${RESET}"
    echo "${GREEN}3. Sign server certificate with CA${RESET}"
    echo "${GREEN}4. Create client truststore${RESET}"
    echo "${GREEN}5. Generate all TLS configuration${RESET}"
    read FUNCTION_CHOICE
	case $FUNCTION_CHOICE in
		1)  FUNCTION=createCA
            ;;
        2)  FUNCTION=createTLSKeyAndCsr
			;;
		3)  FUNCTION=signCertificate
            ;;
        4)  FUNCTION=createClientTruststore
            ;;
        5)  FUNCTION=createTLSConfiguration
            ;;
		*) 	printf "\n${RED}No valid option selected${RESET}\n"
			chooseFunction
			;;
	esac
}

createCA()
{
    echo ${BLU}****************************************************${RESET}
    echo ${BLU}***** Generate our own Certification Authority *****${RESET}
    echo ${BLU}****************************************************${RESET}
    echo 

    ###########################################################################################################################################
    # A certificate authority (CA) is responsible for signing certificates. In this case we will be our own Certificate Authority.            #
    #                                                                                                                                         #
    # With these steps done we can now generate our own CA that will be used to sign certificates later.                                      #
    # The CA is simply a public/private key pair and certificate that is signed by itself, and is only intended to sign other certificates.   #
    ###########################################################################################################################################
    echo ${BLU}***** Creating $DEFAULT_CA_KEYSTORE CA keystore containing a key pair that will be used to sign $DEFAULT_CACERT CA certificate ... ${RESET}

    CMD_KEYSTORE_RUN="keytool -genkeypair -keyalg RSA -keysize 2048 -validity $DEFAULT_VALIDITY -keystore $DEFAULT_TLS_DIR/$DEFAULT_CA_KEYSTORE -alias $DEFAULT_CA_ALIAS"
    echo ${CYAN}Generating CA keystore using following command:${RESET} ${GREEN}$CMD_KEYSTORE_RUN${RESET}
    $CMD_KEYSTORE_RUN
    echo
    
    CMD_CERTIFICATE_RUN="keytool -exportcert -keystore $DEFAULT_TLS_DIR/$DEFAULT_CA_KEYSTORE -alias $DEFAULT_CA_ALIAS -file $DEFAULT_TLS_DIR/$DEFAULT_CACERT"
    echo ${CYAN}Generating $DEFAULT_CACERT CA certificate using following command:${RESET} ${GREEN}$CMD_CERTIFICATE_RUN${RESET}
    $CMD_CERTIFICATE_RUN
    echo

    CMD_CERTIFICATE_RUN="openssl x509 -inform der -in $DEFAULT_TLS_DIR/$DEFAULT_CACERT -out $DEFAULT_TLS_DIR/$DEFAULT_CACERT_PEM"
    echo ${CYAN}Converting CA certificate to PEM format using following command:${RESET} ${GREEN}$CMD_CERTIFICATE_RUN${RESET}
    $CMD_CERTIFICATE_RUN
    echo
}

createTLSKeyAndCsr()
{
    echo ${BLU}*****************************************************************${RESET}
    echo ${BLU}***** Generate TLS keystore and Certificate Signing Request *****${RESET}
    echo ${BLU}*****************************************************************${RESET}
    echo

    ##################################################################################################
    # The first step of deploying Keycloak with TLS support is to generate a public/private keypair. #
    # We will use Java's keytool command for this task.                                              #
    ##################################################################################################
    echo ${BLU}***** Creating new keystore with alias $DEFAULT_KEYSTORE_ALIAS ...${RESET}
    if [ -z $KEYSTORE ]; then 
		inputKeystore
	fi
    if [ -z $VALIDITY ]; then 
		inputValidity
	fi
    CMD_RUN="keytool -genkeypair -keystore $DEFAULT_TLS_DIR/$KEYSTORE -alias $DEFAULT_KEYSTORE_ALIAS -keyalg RSA -keysize 2048 -validity $DEFAULT_VALIDITY"
    echo ${CYAN}Creating keystore using following command:${RESET} ${GREEN}$CMD_RUN${RESET}
    $CMD_RUN
    echo

    ##########################################################################################################################################
    # To obtain a certificate that can be used with the private key that was just created a certificate signing request needs to be created. #
    # This signing request, when signed by a trusted CA results in the actual certificate which can then be installed in the keystore and    #
    # used for authentication purposes.                                                                                                      #
    ##########################################################################################################################################
    echo ${BLU}***** Generating $DEFAULT_CSR Certificate Signing Request from $KEYSTORE keystore ...${RESET}
    CMD_RUN="keytool -certreq -keystore $DEFAULT_TLS_DIR/$KEYSTORE -alias $DEFAULT_KEYSTORE_ALIAS -file $DEFAULT_TLS_DIR/$DEFAULT_CSR"
    echo ${CYAN}Generating CSR using following command:${RESET} ${GREEN}$CMD_RUN${RESET}
    $CMD_RUN
    echo
}

signCertificate()
{
    echo ${BLU}***************************************${RESET}
    echo ${BLU}***** Sign the server certificate *****${RESET}
    echo ${BLU}***************************************${RESET}
    echo 

    ############################################################################################
    # Create a server certificate signing the Certificate Signing Request using CA certificate #
    ############################################################################################
    echo ${BLU}***** Signing $DEFAULT_SERVER_CERTIFICATE server certificate using CA certificate within $DEFAULT_CA_KEYSTORE CA keystore ... ${RESET}
    CMD_RUN="keytool -gencert -keystore $DEFAULT_TLS_DIR/$DEFAULT_CA_KEYSTORE -alias $DEFAULT_CA_ALIAS -infile $DEFAULT_TLS_DIR/$DEFAULT_CSR -outfile $DEFAULT_TLS_DIR/$DEFAULT_SERVER_CERTIFICATE -validity $DEFAULT_VALIDITY"
    echo ${CYAN}Signing certificate with CA using following command:${RESET} ${GREEN}$CMD_RUN${RESET}
    $CMD_RUN
    echo 

    #######################################
    # Import CA certificate into keystore #
    #######################################
    echo ${BLU}***** Importing $DEFAULT_CACERT CA certificate into server keystore ... ${RESET}
    if [ -z $KEYSTORE ]; then 
		inputKeystore
	fi
    CMD_RUN="keytool -import -keystore $DEFAULT_TLS_DIR/$KEYSTORE -file $DEFAULT_TLS_DIR/$DEFAULT_CACERT -alias $DEFAULT_CA_ALIAS"
    echo ${CYAN}Importing CA certificate in keystore using following command:${RESET} ${GREEN}$CMD_RUN${RESET}
    $CMD_RUN
    echo 
    
    ######################################################
    # Import the signed server certificate into keystore #
    ######################################################
    echo ${BLU}***** Importing $DEFAULT_SERVER_CERTIFICATE signed server certificate into $DEFAULT_KEYSTORE keystore ... ${RESET}
    CMD_RUN="keytool -importcert -keystore $DEFAULT_TLS_DIR/$DEFAULT_KEYSTORE -alias $DEFAULT_KEYSTORE_ALIAS -file $DEFAULT_TLS_DIR/$DEFAULT_SERVER_CERTIFICATE"
    echo ${CYAN}Importing signed certificate into keystore using following command:${RESET} ${GREEN}$CMD_RUN${RESET}
    $CMD_RUN
    echo
}

createClientTruststore()
{
    echo ${BLU}**************************************${RESET}
    echo ${BLU}***** Generate client truststore *****${RESET}
    echo ${BLU}**************************************${RESET}
    echo 

    ###########################################################################################################################
    # The next step is to add the generated CA to the **clients' truststore** so that the clients can trust this CA.          #
    # In contrast to the keystore in step 1, the truststore of a client stores all the certificates that                      #
    # the client should trust.                                                                                                #
    #                                                                                                                         #
    # Importing a certificate into one's truststore also means trusting all certificates that are signed by that certificate. #
    # This attribute is called the chain of trust.                                                                            #
    ###########################################################################################################################
    echo ${BLU}***** Importing $DEFAULT_CACERT_PEM Self CA certificate into JKS formatted truststore ... ${RESET}
    if [ -z $TRUSTSTORE ]; then 
		inputTruststore
	fi
    CMD_RUN="keytool -importcert -file $DEFAULT_TLS_DIR/$DEFAULT_CACERT_PEM -alias $DEFAULT_CA_ALIAS -keystore $DEFAULT_TRUSTSTORE_DIR/$TRUSTSTORE"
    echo ${CYAN}Importing Self CA certificate into client truststore using following command:${RESET} ${GREEN}$CMD_RUN${RESET}
    $CMD_RUN
    echo

    echo ${BLU}***** Importing $DEFAULT_KEYSTORE server certificate self signed with $DEFAULT_CACERT_PEM CA certificate into $TRUSTSTORE JKS formatted truststore ... ${RESET}   
    CMD_RUN="keytool -importkeystore -srckeystore $DEFAULT_TLS_DIR/$DEFAULT_KEYSTORE -destkeystore $DEFAULT_TRUSTSTORE_DIR/$TRUSTSTORE"
    echo ${CYAN}Importing self signed server certificate into client truststore using following command:${RESET} ${GREEN}$CMD_RUN${RESET}
    $CMD_RUN
    echo
    
    echo ${BLU}***** Converting $TRUSTSTORE JKS truststore to $DEFAULT_PKCS12_TRUSTSTORE PKCS12 truststore for non Java clients ... ${RESET}
    CMD_PKCS_RUN="keytool -importkeystore -srckeystore $DEFAULT_TRUSTSTORE_DIR/$TRUSTSTORE -destkeystore $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_PKCS12_TRUSTSTORE -srcstoretype JKS -deststoretype PKCS12"
    echo ${CYAN}Converting JKS truststore to PKCS12 format using following command:${RESET} ${GREEN}$CMD_PKCS_RUN${RESET}
    $CMD_PKCS_RUN
    echo
    
    echo ${BLU}***** Converting $DEFAULT_PKCS12_TRUSTSTORE PKCS12 truststore to $DEFAULT_PEM_TRUSTSTORE PEM truststore for non Java clients ... ${RESET}
    CMD_PEM_RUN="openssl pkcs12 -in $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_PKCS12_TRUSTSTORE -out $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_PEM_TRUSTSTORE -nodes"
    echo ${CYAN}Converting PKCS12 truststore to PEM format using following command:${RESET} ${GREEN}$CMD_PEM_RUN${RESET}
    $CMD_PEM_RUN
    echo
}

createTLSConfiguration()
{
    createCA
    createTLSKeyAndCsr
    signCertificate
    createClientTruststore
}

inputKeystore()
{
    ###### Set keystore name
    if [ "$KEYSTORE" != "" ]; then
        echo Keystore is set to $KEYSTORE
    else
        echo ${GREEN}Enter keystore - leaving blank will set keystore to ${RESET}${MAGENTA}$DEFAULT_KEYSTORE : ${RESET}
        read KEYSTORE
        if [ "$KEYSTORE" == "" ]; then
            KEYSTORE=$DEFAULT_KEYSTORE
        fi
    fi
}

inputValidity()
{
    ###### Set validity days
    if [ "$VALIDITY" != "" ]; then
        echo Validity days are set to $VALIDITY
    else
        echo ${GREEN}Enter keystore validity days - leaving blank will set validaty days to ${RESET}${MAGENTA}$DEFAULT_VALIDITY : ${RESET}
        read VALIDITY
        if [ "$VALIDITY" == "" ]; then
            VALIDITY=$DEFAULT_VALIDITY
        fi
    fi
}

inputTruststore()
{
    ###### Set truststore name
    if [ "$TRUSTSTORE" != "" ]; then
        echo Truststore is set to $TRUSTSTORE
    else
        echo ${GREEN}Enter truststore - leaving blank will set truststore to ${RESET}${MAGENTA}$DEFAULT_TRUSTSTORE : ${RESET}
        read TRUSTSTORE
        if [ "$TRUSTSTORE" == "" ]; then
            TRUSTSTORE=$DEFAULT_TRUSTSTORE
        fi
    fi
}
# ***** Function section - END

# ##############################################
# #################### MAIN ####################
# ##############################################
chooseFunction
main