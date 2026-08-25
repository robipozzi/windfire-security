source ./common.sh
# ##### Variable section - START
SCRIPT=start-keycloak.sh
PLATFORM_OPTION=
KEYCLOAK_USERNAME=
KEYCLOAK_PASSWORD=
KEYSTORE_PASSWORD=
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
    echo "${GREEN}1. Run server (No TLS)${RESET}"
	echo "${GREEN}2. Run server (TLS enabled)${RESET}"
	echo "${GREEN}3. Run Docker${RESET}"
	read PLATFORM_OPTION
	
	case $PLATFORM_OPTION in
		1) 	selectLogLevel
			echo ${BLU}"Keycloak will start with $LOG_LEVEL log level..."${RESET}
			# Check if the admin user has already been created
			if [ ! -f "$KEYCLOAK_HOME/data/.admin_created" ]; then
				setupAdminAndStart "NOSSL"
			else
				# Start Keycloak in development mode with the specified log level
				sudo $KEYCLOAK_HOME/bin/kc.sh start-dev --log-level=$LOG_LEVEL > keycloak.log 2>&1 &
			fi
			;;
		2)  selectLogLevel
			echo ${BLU}"Keycloak will start with $LOG_LEVEL log level..."${RESET}
			if [ -z $KEYSTORE_PASSWORD ]; then 
				inputKeystorePassword
			fi
			# Check if the admin user has already been created
			if [ ! -f "$KEYCLOAK_HOME/data/.admin_created" ]; then
				setupAdminAndStart "SSL"
			fi
			sudo $KEYCLOAK_HOME/bin/kc.sh start --http-enabled=false --https-key-store-password=$KEYSTORE_PASSWORD --hostname=localhost --log-level=$LOG_LEVEL > keycloak.log 2>&1 &
			;;
        3)  inputKeycloakUsername
			inputKeycloakPassword
			selectLogLevel
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

setupAdminAndStart()
{
    echo ${BLU}*************************************${RESET}
    echo ${BLU}***** Setup Keycloak Admin user *****${RESET}
    echo ${BLU}*************************************${RESET}
    echo
    inputKeycloakUsername
	inputKeycloakPassword
	export KEYCLOAK_ADMIN_USER=$KEYCLOAK_USERNAME
	export KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_PASSWORD

	echo ${BLU}"Starting Keycloak with $KEYCLOAK_USERNAME as administration user..."${RESET}
	case $1 in
		NOSSL) 	echo ${BLU}"Starting Keycloak with NO SSL enabled, console accessible on http ..."${RESET}
				sudo KEYCLOAK_ADMIN=$KEYCLOAK_USERNAME KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_PASSWORD $KEYCLOAK_HOME/bin/kc.sh start-dev --log-level=$LOG_LEVEL > keycloak.log 2>&1 &
				sudo touch "$KEYCLOAK_HOME/data/.admin_created"
				;;
		SSL)	echo ${BLU}"Starting Keycloak with SSL enabled, console accessible on https ..."${RESET}
				sudo KEYCLOAK_ADMIN=$KEYCLOAK_USERNAME KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_PASSWORD $KEYCLOAK_HOME/bin/kc.sh start --http-enabled=false --https-key-store-password=$KEYSTORE_PASSWORD --hostname=localhost --log-level=$LOG_LEVEL > keycloak.log 2>&1 &
				sudo touch "$KEYCLOAK_HOME/data/.admin_created"
				;;
		*)		echo ${RED}"Invalid option. Please use 'NOSSL', or 'SSL'."${RESET}
            	;;
	esac
}

inputKeycloakUsername()
{
	echo ${GREEN}Input Keycloak Username : ${RESET}
	read KEYCLOAK_USERNAME
	if [ -z $KEYCLOAK_USERNAME ]; then
		echo ${RED}No Keycloak Username input${RESET}
		inputKeycloakUsername
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

inputKeystorePassword()
{
	echo ${GREEN}Input Keystore Password : ${RESET}
	read -s KEYSTORE_PASSWORD
	if [ -z $KEYSTORE_PASSWORD ]; then
		echo ${RED}No Keystore Password input${RESET}
		inputKeystorePassword
	fi
}
# ***** Function section - END

# ##############################################
# #################### MAIN ####################
# ##############################################
main