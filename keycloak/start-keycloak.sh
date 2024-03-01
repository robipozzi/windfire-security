source ../setenv.sh
# ##### Variable section - START
SCRIPT=start-keycloak.sh
PLATFORM_OPTION=
KEYSTORE_PASSWORD=
KEYCLOAK_PASSWORD=
# ##### Variable section - END

# ***** Function section - START
###########################
## Start Keycloak Server ##
###########################
main()
{
	runSelectPlatform
}

runSelectPlatform()
{
	echo ${grn}Select Keycloak run platform : ${end}
    echo "${grn}1. Server on Localhost${end}"
	echo "${grn}2. Server on Localhost (SSL enabled)${end}"
	echo "${grn}3. Docker${end}"
	read PLATFORM_OPTION
	setPlatform
}

setPlatform()
{
	case $PLATFORM_OPTION in
		1)  $KEYCLOAK_HOME/bin/kc.sh start-dev
			;;
		2)  if [ -z $KEYSTORE_PASSWORD ]; then 
				inputKeystorePassword
			fi
			echo $KEYCLOAK_HOME/bin/kc.sh start --http-enabled=false --https-key-store-password=$KEYSTORE_PASSWORD --hostname=localhost
			;;
        3)  if [ -z $KEYCLOAK_PASSWORD ]; then 
				inputKeycloakPassword
			fi
			docker run -p $KEYCLOAK_PORT:8080 -e KEYCLOAK_ADMIN=$KEYCLOAK_USERNAME -e KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_PASSWORD --name $KEYCLOAK_CONTAINER_NAME $KEYCLOAK_DOCKER_IMAGE:$KEYCLOAK_DOCKER_IMAGE_VERSION start-dev
			;;       
		*) 	printf "\n${red}No valid option selected${end}\n"
			runSelectPlatform
			;;
	esac
}

inputKeystorePassword()
{
	echo ${grn}Input Keystore Password : ${end}
	read -s KEYSTORE_PASSWORD
	setKeystorePassword
}

setKeystorePassword()
{  
	if [ -z $KEYSTORE_PASSWORD ]; then
		echo ${red}No Keystore Password input${end}
		inputKeystorePassword
	fi
}

inputKeycloakPassword()
{
	echo ${grn}Input Keycloak Password : ${end}
	read -s KEYCLOAK_PASSWORD
	setKeycloakPassword
}

setKeycloakPassword()
{  
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