source ../../setenv.sh

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
	echo ${grn}Choose function : ${end}
    echo "${grn}1. Create our own Certification Authority${end}"
    echo "${grn}2. Generate server keystore and certificate signing request${end}"
    echo "${grn}3. Sign server certificate with CA${end}"
    echo "${grn}4. Create client truststore${end}"
    echo "${grn}5. Generate all TLS configuration${end}"
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
		*) 	printf "\n${red}No valid option selected${end}\n"
			chooseFunction
			;;
	esac
}

createCA()
{
    echo ${blu}****************************************************${end}
    echo ${blu}***** Generate our own Certification Authority *****${end}
    echo ${blu}****************************************************${end}
    echo 

    ###########################################################################################################################################
    # A certificate authority (CA) is responsible for signing certificates. In this case we will be our own Certificate Authority.            #
    #                                                                                                                                         #
    # With these steps done we can now generate our own CA that will be used to sign certificates later.                                      #
    # The CA is simply a public/private key pair and certificate that is signed by itself, and is only intended to sign other certificates.   #
    ###########################################################################################################################################
    echo ${blu}***** Creating $DEFAULT_CA_KEYSTORE CA keystore containing a key pair that will be used to sign $DEFAULT_CACERT CA certificate ... ${end}

    CMD_KEYSTORE_RUN="keytool -genkeypair -keyalg RSA -keysize 2048 -validity $DEFAULT_VALIDITY -keystore $DEFAULT_TLS_DIR/$DEFAULT_CA_KEYSTORE -alias $DEFAULT_CA_ALIAS"                      
    echo ${cyn}Generating CA keystore using following command:${end} ${grn}$CMD_KEYSTORE_RUN${end}
    $CMD_KEYSTORE_RUN
    echo
    
    CMD_CERTIFICATE_RUN="keytool -exportcert -keystore $DEFAULT_TLS_DIR/$DEFAULT_CA_KEYSTORE -alias $DEFAULT_CA_ALIAS -file $DEFAULT_TLS_DIR/$DEFAULT_CACERT"
    echo ${cyn}Generating $DEFAULT_CACERT CA certificate using following command:${end} ${grn}$CMD_CERTIFICATE_RUN${end}
    $CMD_CERTIFICATE_RUN
    echo

    CMD_CERTIFICATE_RUN="openssl x509 -inform der -in $DEFAULT_TLS_DIR/$DEFAULT_CACERT -out $DEFAULT_TLS_DIR/$DEFAULT_CACERT_PEM"
    echo ${cyn}Converting CA certificate to PEM format using following command:${end} ${grn}$CMD_CERTIFICATE_RUN${end}
    $CMD_CERTIFICATE_RUN
    echo
}

createTLSKeyAndCsr()
{
    echo ${blu}*****************************************************************${end}
    echo ${blu}***** Generate TLS keystore and Certificate Signing Request *****${end}
    echo ${blu}*****************************************************************${end}
    echo

    ##################################################################################################
    # The first step of deploying Keycloak with TLS support is to generate a public/private keypair. #
    # We will use Java's keytool command for this task.                                              #
    ##################################################################################################
    echo ${blu}***** Creating new keystore with alias $DEFAULT_KEYSTORE_ALIAS ...${end}
    if [ -z $KEYSTORE ]; then 
		inputKeystore
	fi
    if [ -z $VALIDITY ]; then 
		inputValidity
	fi
    CMD_RUN="keytool -genkeypair -keystore $DEFAULT_TLS_DIR/$KEYSTORE -alias $DEFAULT_KEYSTORE_ALIAS -keyalg RSA -keysize 2048 -validity $DEFAULT_VALIDITY"
    echo ${cyn}Creating keystore using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo

    ##########################################################################################################################################
    # To obtain a certificate that can be used with the private key that was just created a certificate signing request needs to be created. #
    # This signing request, when signed by a trusted CA results in the actual certificate which can then be installed in the keystore and    #
    # used for authentication purposes.                                                                                                      #
    ##########################################################################################################################################
    echo ${blu}***** Generating $DEFAULT_CSR Certificate Signing Request from $KEYSTORE keystore ...${end}
    CMD_RUN="keytool -certreq -keystore $DEFAULT_TLS_DIR/$KEYSTORE -alias $DEFAULT_KEYSTORE_ALIAS -file $DEFAULT_TLS_DIR/$DEFAULT_CSR"
    echo ${cyn}Generating CSR using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo
}

signCertificate()
{
    echo ${blu}***************************************${end}
    echo ${blu}***** Sign the server certificate *****${end}
    echo ${blu}***************************************${end}
    echo 

    ############################################################################################
    # Create a server certificate signing the Certificate Signing Request using CA certificate #
    ############################################################################################
    echo ${blu}***** Signing $DEFAULT_SERVER_CERTIFICATE server certificate using CA certificate within $DEFAULT_CA_KEYSTORE CA keystore ... ${end}
    CMD_RUN="keytool -gencert -keystore $DEFAULT_TLS_DIR/$DEFAULT_CA_KEYSTORE -alias $DEFAULT_CA_ALIAS -infile $DEFAULT_TLS_DIR/$DEFAULT_CSR -outfile $DEFAULT_TLS_DIR/$DEFAULT_SERVER_CERTIFICATE -validity $DEFAULT_VALIDITY"
    echo ${cyn}Signing certificate with CA using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo 

    #######################################
    # Import CA certificate into keystore #
    #######################################
    echo ${blu}***** Importing $DEFAULT_CACERT CA certificate into server keystore ... ${end}
    if [ -z $KEYSTORE ]; then 
		inputKeystore
	fi
    CMD_RUN="keytool -import -keystore $DEFAULT_TLS_DIR/$KEYSTORE -file $DEFAULT_TLS_DIR/$DEFAULT_CACERT -alias $DEFAULT_CA_ALIAS"
    echo ${cyn}Importing CA certificate in keystore using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo 
    
    ######################################################
    # Import the signed server certificate into keystore #
    ######################################################
    echo ${blu}***** Importing $DEFAULT_SERVER_CERTIFICATE signed server certificate into $DEFAULT_KEYSTORE keystore ... ${end}
    CMD_RUN="keytool -importcert -keystore $DEFAULT_TLS_DIR/$DEFAULT_KEYSTORE -alias $DEFAULT_KEYSTORE_ALIAS -file $DEFAULT_TLS_DIR/$DEFAULT_SERVER_CERTIFICATE"
    echo ${cyn}Importing signed certificate into keystore using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo
}

createClientTruststore()
{
    echo ${blu}**************************************${end}
    echo ${blu}***** Generate client truststore *****${end}
    echo ${blu}**************************************${end}
    echo 

    ###########################################################################################################################
    # The next step is to add the generated CA to the **clients' truststore** so that the clients can trust this CA.          #
    # In contrast to the keystore in step 1, the truststore of a client stores all the certificates that                      #
    # the client should trust.                                                                                                #
    #                                                                                                                         #
    # Importing a certificate into one's truststore also means trusting all certificates that are signed by that certificate. #
    # This attribute is called the chain of trust.                                                                            #
    ###########################################################################################################################
    echo ${blu}***** Importing $DEFAULT_CACERT_PEM Self CA certificate into JKS formatted truststore ... ${end}
    if [ -z $TRUSTSTORE ]; then 
		inputTruststore
	fi
    CMD_RUN="keytool -importcert -file $DEFAULT_TLS_DIR/$DEFAULT_CACERT_PEM -alias $DEFAULT_CA_ALIAS -keystore $DEFAULT_TRUSTSTORE_DIR/$TRUSTSTORE"
    echo ${cyn}Importing Self CA certificate into client truststore using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo

    echo ${blu}***** Importing $DEFAULT_KEYSTORE server certificate self signed with $DEFAULT_CACERT_PEM CA certificate into $TRUSTSTORE JKS formatted truststore ... ${end}   
    CMD_RUN="keytool -importkeystore -srckeystore $DEFAULT_TLS_DIR/$DEFAULT_KEYSTORE -destkeystore $DEFAULT_TRUSTSTORE_DIR/$TRUSTSTORE"
    echo ${cyn}Importing self signed server certificate into client truststore using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo
    
    echo ${blu}***** Converting $TRUSTSTORE JKS truststore to $DEFAULT_PKCS12_TRUSTSTORE PKCS12 truststore for non Java clients ... ${end}
    CMD_PKCS_RUN="keytool -importkeystore -srckeystore $DEFAULT_TRUSTSTORE_DIR/$TRUSTSTORE -destkeystore $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_PKCS12_TRUSTSTORE -srcstoretype JKS -deststoretype PKCS12"
    echo ${cyn}Converting JKS truststore to PKCS12 format using following command:${end} ${grn}$CMD_PKCS_RUN${end}
    $CMD_PKCS_RUN
    echo
    
    echo ${blu}***** Converting $DEFAULT_PKCS12_TRUSTSTORE PKCS12 truststore to $DEFAULT_PEM_TRUSTSTORE PEM truststore for non Java clients ... ${end}
    CMD_PEM_RUN="openssl pkcs12 -in $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_PKCS12_TRUSTSTORE -out $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_PEM_TRUSTSTORE -nodes"
    echo ${cyn}Converting PKCS12 truststore to PEM format using following command:${end} ${grn}$CMD_PEM_RUN${end}
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
        echo ${grn}Enter keystore - leaving blank will set keystore to ${end}${mag}$DEFAULT_KEYSTORE : ${end}
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
        echo ${grn}Enter keystore validity days - leaving blank will set validaty days to ${end}${mag}$DEFAULT_VALIDITY : ${end}
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
        echo ${grn}Enter truststore - leaving blank will set truststore to ${end}${mag}$DEFAULT_TRUSTSTORE : ${end}
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