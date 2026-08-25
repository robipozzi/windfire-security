source ../common.sh

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
	echo ${GREEN}Choose function : ${RESET}
    echo "${GREEN}1. Enable Keycloak TLS${RESET}"
    echo "${GREEN}2. Disable Keycloak TLS${RESET}"
	read FUNCTION_CHOICE
	case $FUNCTION_CHOICE in
		1)  FUNCTION=enableTLS
			;;
        2)  FUNCTION=disableTLS
            ;;
		*) 	printf "\n${RED}No valid option selected${RESET}\n"
			chooseFunction
			;;
	esac
}

enableTLS()
{
    echo ${BLU}*******************************************${RESET}
    echo ${BLU}***** Enable Keycloak to run with TLS *****${RESET}
    echo ${BLU}*******************************************${RESET}
    echo

    echo ${BLU}***** Copying $DEFAULT_KEYSTORE server keystore to $KEYCLOAK_HOME/conf ...${RESET}
    cp $DEFAULT_TLS_DIR/$DEFAULT_KEYSTORE $KEYCLOAK_HOME/conf
    echo
    
    #echo ${BLU}***** Copying $DEFAULT_CACERT_PEM CA PEM certificate to $KEYCLOAK_HOME/conf/truststores ...${RESET}
    #mkdir $KEYCLOAK_HOME/conf/truststores
    #cp $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_CACERT_PEM $KEYCLOAK_HOME/conf/truststores/$DEFAULT_CACERT_PEM
    #echo
    
    echo ${BLU}***** Rebuilding Keycloak configuration ...${RESET}
    CMD_RUN="$KEYCLOAK_HOME/bin/kc.sh build"
    echo ${CYAN}Rebuilding Keycloak configuration using following command:${RESET} ${GREEN}$CMD_RUN${RESET}
    $CMD_RUN
    echo
    echo ${BLU}***** Keycloak is set to run with TLS enabled${RESET}
    echo
}

disableTLS()
{
    echo ${BLU}**********************************************${RESET}
    echo ${BLU}***** Disable Keycloak TLS configuration *****${RESET}
    echo ${BLU}**********************************************${RESET}
    echo

    echo ${BLU}***** Removing $DEFAULT_KEYSTORE from $KEYCLOAK_HOME/conf ...${RESET}
    rm -rf $KEYCLOAK_HOME/conf/$DEFAULT_KEYSTORE
    echo
    
    #echo ${BLU}***** Removing $DEFAULT_CACERT_PEM CA PEM Certificate from $KEYCLOAK_HOME/conf/truststores ...${RESET}
    #rm -rf $KEYCLOAK_HOME/conf/truststores/$DEFAULT_CACERT_PEM
    #echo
    
    echo ${BLU}***** Keycloak is set to run with TLS disabled${RESET}
    echo
}
# ***** Function section - END

# ##############################################
# #################### MAIN ####################
# ##############################################
chooseFunction
main