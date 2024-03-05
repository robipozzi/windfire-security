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

printChooseFunction()
{
	echo ${grn}Choose function : ${end}
    echo "${grn}1. Generate server keystore and certificate signing request${end}"
    echo "${grn}2. Create our own Certification Authority${end}"
    echo "${grn}3. Sign server certificate with CA${end}"
    echo "${grn}4. Create client truststore${end}"
    echo "${grn}5. Generate all TLS configuration${end}"
    read FUNCTION_CHOICE
	setFunctionChoice
}

setFunctionChoice()
{
	case $FUNCTION_CHOICE in
		1)  FUNCTION=createTLSKeyAndCsr
			;;
		2)  FUNCTION=createCA
            ;;
		3)  FUNCTION=signCertificate
            ;;
        4)  FUNCTION=createClientTruststore
            ;;
        5)  FUNCTION=createTLSConfiguration
            ;;
		*) 	printf "\n${red}No valid option selected${end}\n"
			printChooseFunction
			;;
	esac
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
    echo ${blu}***** Creating a new keystore ...${end}
    if [ -z $KEYSTORE ]; then 
		inputKeystore
	fi
    if [ -z $VALIDITY ]; then 
		inputValidity
	fi
    CMD_RUN="keytool -genkeypair -keystore $DEFAULT_TLS_DIR/$KEYSTORE -alias $DEFAULT_KEYSTORE_ALIAS -keyalg RSA -keysize 2048"
    echo ${cyn}Creating keystore using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo

    ##########################################################################################################################################
    # To obtain a certificate that can be used with the private key that was just created a certificate signing request needs to be created. #
    # This signing request, when signed by a trusted CA results in the actual certificate which can then be installed in the keystore and    #
    # used for authentication purposes.                                                                                                      #
    ##########################################################################################################################################
    echo ${blu}***** Generating a Certificate Signing Request from keystore ...${end}
    CMD_RUN="keytool -certreq -keystore $DEFAULT_TLS_DIR/$KEYSTORE -alias $DEFAULT_KEYSTORE_ALIAS -file $DEFAULT_TLS_DIR/$DEFAULT_CSR"
    echo ${cyn}Generating CSR using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo
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
    echo ${blu}***** Creating CA private key and CA certificate ... ${end}
    CMD_KEYSTORE_RUN="keytool -genkeypair -keyalg RSA -keysize 2048 -keystore $DEFAULT_TLS_DIR/$DEFAULT_CA_KEYSTORE -alias $DEFAULT_CA_ALIAS"
    echo ${cyn}Generating CA keystore using following command:${end} ${grn}$CMD_KEYSTORE_RUN${end}
    $CMD_KEYSTORE_RUN
    echo
    
    CMD_CERTIFICATE_RUN="keytool -export -keystore $DEFAULT_TLS_DIR/$DEFAULT_CA_KEYSTORE -alias $DEFAULT_CA_ALIAS -file $DEFAULT_TLS_DIR/$DEFAULT_CACERT"
    echo ${cyn}Generating CA certificate using following command:${end} ${grn}$CMD_CERTIFICATE_RUN${end}
    $CMD_CERTIFICATE_RUN
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
    echo ${blu}***** Signing server certificate using CA certificate ... ${end}
    CMD_RUN="keytool -gencert -keystore $DEFAULT_TLS_DIR/$DEFAULT_CA_KEYSTORE -alias $DEFAULT_CA_ALIAS -infile $DEFAULT_TLS_DIR/$DEFAULT_CSR -outfile $DEFAULT_TLS_DIR/$DEFAULT_SERVER_CERTIFICATE"
    echo ${cyn}Signing certificate with CA using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo 

    #######################################
    # Import CA certificate into keystore #
    #######################################
    echo ${blu}***** Importing CA certificate into keystore ... ${end}
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
    echo ${blu}***** Importing signed server certificate into keystore ... ${end}
    CMD_RUN="keytool -import -keystore $DEFAULT_TLS_DIR/$DEFAULT_KEYSTORE -file $DEFAULT_TLS_DIR/$DEFAULT_SERVER_CERTIFICATE -alias $DEFAULT_KEYSTORE_ALIAS"
    echo ${cyn}Importing signed certificate into keystore using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo

    echo ${blu}***** Deleting Server Certificate Signing Request ... ${end}
    rm -rf $DEFAULT_TLS_DIR/$DEFAULT_CSR
    echo
    
    echo ${blu}***** Deleting CA keystore ... ${end}
    rm -rf $DEFAULT_TLS_DIR/$DEFAULT_CA_KEYSTORE
    echo
    
    echo ${blu}***** Deleting Server certificate ... ${end}
    rm -rf $DEFAULT_TLS_DIR/$DEFAULT_SERVER_CERTIFICATE
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
    # In contrast to the keystore in step 1 that stores each machine's own identity, the truststore of a client stores        #
    # all the certificates that the client should trust.                                                                      #
    #                                                                                                                         #
    # Importing a certificate into one's truststore also means trusting all certificates that are signed by that certificate. #
    # This attribute is called the chain of trust, and it is particularly useful when deploying TLS on a large Kafka cluster. #
    ###########################################################################################################################
    echo ${blu}***** Creating a new client JKS formatted truststore and import CA certificate ... ${end}
    if [ -z $TRUSTSTORE ]; then 
		inputTruststore
	fi
    CMD_RUN="keytool -keystore $DEFAULT_TRUSTSTORE_DIR/$TRUSTSTORE -alias $DEFAULT_CA_ALIAS -import -file $DEFAULT_TLS_DIR/$DEFAULT_CACERT"
    echo ${cyn}Generating client truststore using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo
    
    echo ${blu}***** Converting JKS truststore to PEM format for non Java clients ... ${end}
    CMD_PKCS_RUN="keytool -importkeystore -srckeystore $DEFAULT_TRUSTSTORE_DIR/$TRUSTSTORE -destkeystore $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_PKCS12_TRUSTSTORE -srcstoretype JKS -deststoretype PKCS12"
    echo ${cyn}Converting JKS truststore to PKCS12 format using following command:${end} ${grn}$CMD_PKCS_RUN${end}
    $CMD_PKCS_RUN
    echo
    
    CMD_PEM_RUN="openssl pkcs12 -in $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_PKCS12_TRUSTSTORE -out $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_PEM_TRUSTSTORE -nodes"
    echo ${cyn}Converting PKCS12 truststore to PEM format using following command:${end} ${grn}$CMD_PEM_RUN${end}
    $CMD_PEM_RUN
    echo
    
    CMD_CA_PEM_RUN="openssl pkcs12 -in $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_PKCS12_TRUSTSTORE -out $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_CACERT_PEM"
    echo ${cyn}Generating CA PEM formatted certificate using following openssl command:${end} ${grn}$CMD_CA_PEM_RUN${end}
    $CMD_CA_PEM_RUN
    echo   
}

createTLSConfiguration()
{
    createTLSKeyAndCsr
    createCA
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
printChooseFunction
main