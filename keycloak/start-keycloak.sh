source ../common.sh
# ##### Variable section - START
SCRIPT=start-keycloak.sh
PLATFORM_OPTION=
KEYSTORE_PASSWORD=
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
	echo ${grn}Select Keycloak run platform : ${end}
    echo "${grn}1. Server on Localhost (No TLS)${end}"
	echo "${grn}2. Server on Localhost (TLS enabled)${end}"
	echo "${grn}3. Docker${end}"
	read PLATFORM_OPTION
	
	case $PLATFORM_OPTION in
		1)  selectLogLevel
			$KEYCLOAK_HOME/bin/kc.sh start-dev --log-level=$LOG_LEVEL
			;;
		2)  selectLogLevel
			if [ -z $KEYSTORE_PASSWORD ]; then 
				inputKeystorePassword
			fi
			$KEYCLOAK_HOME/bin/kc.sh start --http-enabled=false --https-key-store-password=$KEYSTORE_PASSWORD --hostname=localhost --log-level=$LOG_LEVEL
			;;
        3)  selectLogLevel
			if [ -z $KEYCLOAK_PASSWORD ]; then 
				inputKeycloakPassword
			fi
			docker run -p $KEYCLOAK_PORT:8080 -e KEYCLOAK_ADMIN=$KEYCLOAK_USERNAME -e KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_PASSWORD --name $KEYCLOAK_CONTAINER_NAME $KEYCLOAK_DOCKER_IMAGE:$KEYCLOAK_DOCKER_IMAGE_VERSION start-dev
			;;       
		*) 	printf "\n${red}No valid option selected${end}\n"
			selectPlatform
			;;
	esac
}

selectLogLevel()
{
	echo ${grn}Select Log level for Keycloak : ${end}
    echo "${grn}1. Debug${end}"
	echo "${grn}2. Info${end}"
	echo "${grn}3. Warn${end}"
	echo "${grn}4. Error${end}"
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
		*) 	printf "\n${red}No valid option selected${end}\n"
			selectLogLevel
			;;
	esac
}

inputKeystorePassword()
{
	echo ${grn}Input Keystore Password : ${end}
	read -s KEYSTORE_PASSWORD
	if [ -z $KEYSTORE_PASSWORD ]; then
		echo ${red}No Keystore Password input${end}
		inputKeystorePassword
	fi
}

inputKeycloakPassword()
{
	echo ${grn}Input Keycloak Password : ${end}
	read -s KEYCLOAK_PASSWORD
	if [ -z $KEYCLOAK_PASSWORD ]; then
		echo ${red}No Keycloak Password input${end}
		inputKeycloakPassword
	fi
}
# ***** Function section - END

# ##############################################
# #################### MAIN ####################
# ##############################################
main