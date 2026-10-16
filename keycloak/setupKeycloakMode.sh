#!/bin/bash
source ../common.sh

# ##### Variable section - START
SCRIPT=setupKeycloakMode.sh
FUNCTION_CHOICE=
FUNCTION=
KEYCLOAK_SERVER_CERTIFICATE=$KEYCLOAK_CERT_NAME.crt
KEYCLOAK_SERVER_KEY=$KEYCLOAK_CERT_NAME.key
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

    ###########################################################################################
    # Keycloak server certificate and key (PEM) are signed by Windfire Keycloak Root CA and   #
    # generated for localhost by security/setupTLS.sh (option 2, Development environment).    #
    ###########################################################################################
    if [ ! -f "$DEFAULT_TLS_DIR/$KEYCLOAK_SERVER_CERTIFICATE" ] || [ ! -f "$DEFAULT_TLS_DIR/$KEYCLOAK_SERVER_KEY" ]; then
        echo -e "${RED}Error: Keycloak server certificate/key not found in $DEFAULT_TLS_DIR${RESET}" >&2
        echo -e "${RED}Run security/setupTLS.sh 2 1 first to generate them for localhost${RESET}" >&2
        exit 1
    fi

    echo ${BLU}***** Copying $KEYCLOAK_SERVER_CERTIFICATE server certificate and $KEYCLOAK_SERVER_KEY server key to $KEYCLOAK_CONF_TLS_DIR ...${RESET}
    mkdir -p "$KEYCLOAK_CONF_TLS_DIR" || { echo -e "${RED}Error: failed to create directory: $KEYCLOAK_CONF_TLS_DIR${RESET}" >&2; exit 1; }
    cp "$DEFAULT_TLS_DIR/$KEYCLOAK_SERVER_CERTIFICATE" "$DEFAULT_TLS_DIR/$KEYCLOAK_SERVER_KEY" "$KEYCLOAK_CONF_TLS_DIR/" \
        || { echo -e "${RED}Error: failed to copy server certificate and key to $KEYCLOAK_CONF_TLS_DIR${RESET}" >&2; exit 1; }
    chmod 644 "$KEYCLOAK_CONF_TLS_DIR/$KEYCLOAK_SERVER_CERTIFICATE"
    chmod 600 "$KEYCLOAK_CONF_TLS_DIR/$KEYCLOAK_SERVER_KEY"
    echo

    # Remove the Java keystore used by the previous TLS setup, if still there
    if [ -f "$KEYCLOAK_HOME/conf/server.keystore" ]; then
        echo ${BLU}***** Removing old server.keystore from $KEYCLOAK_HOME/conf ...${RESET}
        rm -f "$KEYCLOAK_HOME/conf/server.keystore"
        echo
    fi

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

    echo ${BLU}***** Removing $KEYCLOAK_SERVER_CERTIFICATE and $KEYCLOAK_SERVER_KEY from $KEYCLOAK_CONF_TLS_DIR ...${RESET}
    rm -f "$KEYCLOAK_CONF_TLS_DIR/$KEYCLOAK_SERVER_CERTIFICATE" "$KEYCLOAK_CONF_TLS_DIR/$KEYCLOAK_SERVER_KEY"
    echo

    echo ${BLU}***** Keycloak is set to run with TLS disabled${RESET}
    echo
}
# ***** Function section - END

# ##############################################
# #################### MAIN ####################
# ##############################################
chooseFunction
main
