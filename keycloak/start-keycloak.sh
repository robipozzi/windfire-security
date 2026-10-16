#!/bin/bash
source ../common.sh
# ##### Variable section - START
SCRIPT=start-keycloak.sh
PLATFORM_OPTION=
KEYCLOAK_PASSWORD=
DEFAULT_LOG_LEVEL=info
LOG_LEVEL=
# ##### Variable section - END

# ***** Function section - START
###########################
## Start Keycloak Server ##
###########################
main()
{
	selectPlatform
}

selectPlatform()
{
	echo ${GREEN}Select Keycloak run platform : ${RESET}
    echo "${GREEN}1. Server on Localhost (No TLS)${RESET}"
	echo "${GREEN}2. Server on Localhost (TLS enabled)${RESET}"
	echo "${GREEN}3. Docker${RESET}"
	read PLATFORM_OPTION
	
	case $PLATFORM_OPTION in
		1)  selectLogLevel
			$KEYCLOAK_HOME/bin/kc.sh start-dev --log-level=$LOG_LEVEL
			;;
		2)  checkTLSFiles
			selectLogLevel
			$KEYCLOAK_HOME/bin/kc.sh start --http-enabled=false --https-certificate-file=$KEYCLOAK_CONF_TLS_DIR/$KEYCLOAK_CERT_NAME.crt --https-certificate-key-file=$KEYCLOAK_CONF_TLS_DIR/$KEYCLOAK_CERT_NAME.key --hostname=localhost --log-level=$LOG_LEVEL
			;;
        3)  selectLogLevel
			if [ -z $KEYCLOAK_PASSWORD ]; then 
				inputKeycloakPassword
			fi
			docker run -p $KEYCLOAK_PORT:8080 -e KEYCLOAK_ADMIN=$KEYCLOAK_USERNAME -e KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_PASSWORD --name $KEYCLOAK_CONTAINER_NAME $KEYCLOAK_DOCKER_IMAGE:$KEYCLOAK_DOCKER_IMAGE_VERSION start-dev
			;;       
		*) 	printf "\n${RED}No valid option selected${RESET}\n"
			selectPlatform
			;;
	esac
}

selectLogLevel()
{
	echo ${GREEN}Select Log level for Keycloak : ${RESET}
    echo "${GREEN}1. Debug${RESET}"
	echo "${GREEN}2. Info${RESET}"
	echo "${GREEN}3. Warn${RESET}"
	echo "${GREEN}4. Error${RESET}"
	read LOG_LEVEL
	
	case $LOG_LEVEL in
		1)  LOG_LEVEL=debug
			;;
		2)  LOG_LEVEL=info
			;;
        3)  LOG_LEVEL=warn
			;;
		4)  LOG_LEVEL=error
			;;       
		*) 	printf "\n${RED}No valid option selected${RESET}\n"
			selectLogLevel
			;;
	esac
}

checkTLSFiles()
{
	# Keycloak server certificate and key are copied to $KEYCLOAK_CONF_TLS_DIR by setupKeycloakMode.sh (option 1)
	if [ ! -f "$KEYCLOAK_CONF_TLS_DIR/$KEYCLOAK_CERT_NAME.crt" ] || [ ! -f "$KEYCLOAK_CONF_TLS_DIR/$KEYCLOAK_CERT_NAME.key" ]; then
		echo -e "${RED}Error: Keycloak server certificate/key not found in $KEYCLOAK_CONF_TLS_DIR${RESET}" >&2
		echo -e "${RED}Run setupKeycloakMode.sh and select option 1 (Enable Keycloak TLS) first${RESET}" >&2
		exit 1
	fi
}

inputKeycloakPassword()
{
	echo ${GREEN}Input Keycloak Password : ${RESET}
	read -s KEYCLOAK_PASSWORD
	if [ -z $KEYCLOAK_PASSWORD ]; then
		echo ${RED}No Keycloak Password input${RESET}
		inputKeycloakPassword
	fi
}
# ***** Function section - END

# ##############################################
# #################### MAIN ####################
# ##############################################
main