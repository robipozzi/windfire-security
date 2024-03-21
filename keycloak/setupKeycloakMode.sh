source ../setenv.sh

# ##### Variable section - START
SCRIPT=setupKeycloakMode.sh
FUNCTION_CHOICE=
FUNCTION=
# ##### Variable section - END

# ***** Function section - START
main()
{
    $FUNCTION
}

chooseFunction()
{
	echo ${grn}Choose function : ${end}
    echo "${grn}1. Enable Keycloak TLS${end}"
    echo "${grn}2. Disable Keycloak TLS${end}"
	read FUNCTION_CHOICE
	case $FUNCTION_CHOICE in
		1)  FUNCTION=enableTLS
			;;
        2)  FUNCTION=disableTLS
            ;;
		*) 	printf "\n${red}No valid option selected${end}\n"
			chooseFunction
			;;
	esac
}

enableTLS()
{
    echo ${blu}*******************************************${end}
    echo ${blu}***** Enable Keycloak to run with TLS *****${end}
    echo ${blu}*******************************************${end}
    echo

    echo ${blu}***** Copying $DEFAULT_KEYSTORE server keystore to $KEYCLOAK_HOME/conf ...${end}
    cp $DEFAULT_TLS_DIR/$DEFAULT_KEYSTORE $KEYCLOAK_HOME/conf
    echo
    
    #echo ${blu}***** Copying $DEFAULT_CACERT_PEM CA PEM certificate to $KEYCLOAK_HOME/conf/truststores ...${end}
    #mkdir $KEYCLOAK_HOME/conf/truststores
    #cp $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_CACERT_PEM $KEYCLOAK_HOME/conf/truststores/$DEFAULT_CACERT_PEM
    #echo
    
    echo ${blu}***** Rebuilding Keycloak configuration ...${end}
    CMD_RUN="$KEYCLOAK_HOME/bin/kc.sh build"
    echo ${cyn}Rebuilding Keycloak configuration using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo
    echo ${blu}***** Keycloak is set to run with TLS enabled${end}
    echo
}

disableTLS()
{
    echo ${blu}**********************************************${end}
    echo ${blu}***** Disable Keycloak TLS configuration *****${end}
    echo ${blu}**********************************************${end}
    echo

    echo ${blu}***** Removing $DEFAULT_KEYSTORE from $KEYCLOAK_HOME/conf ...${end}
    rm -rf $KEYCLOAK_HOME/conf/$DEFAULT_KEYSTORE
    echo
    
    #echo ${blu}***** Removing $DEFAULT_CACERT_PEM CA PEM Certificate from $KEYCLOAK_HOME/conf/truststores ...${end}
    #rm -rf $KEYCLOAK_HOME/conf/truststores/$DEFAULT_CACERT_PEM
    #echo
    
    echo ${blu}***** Keycloak is set to run with TLS disabled${end}
    echo
}
# ***** Function section - END

# ##############################################
# #################### MAIN ####################
# ##############################################
chooseFunction
main