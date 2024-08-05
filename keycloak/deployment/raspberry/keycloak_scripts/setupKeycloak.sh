source ./setenv.sh

# ##### Variable section - START
SCRIPT=setupKeycloak.sh
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
    echo "${grn}1. Setup Admin user${end}"
    echo "${grn}2. Enable Keycloak TLS${end}"
    echo "${grn}3. Disable Keycloak TLS${end}"
	read FUNCTION_CHOICE
	case $FUNCTION_CHOICE in
        1)  FUNCTION=setupAdmin
			;;
		2)  FUNCTION=enableTLS
			;;
        3)  FUNCTION=disableTLS
            ;;
		*) 	printf "\n${red}No valid option selected${end}\n"
			chooseFunction
			;;
	esac
}

setupAdmin()
{
    echo ${blu}*************************************${end}
    echo ${blu}***** Setup Keycloak Admin user *****${end}
    echo ${blu}*************************************${end}
    echo
    inputKeycloakUsername
	inputKeycloakPassword
	export KEYCLOAK_ADMIN=$KEYCLOAK_USERNAME
	export KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_PASSWORD
    sudo KEYCLOAK_ADMIN=$KEYCLOAK_USERNAME KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_PASSWORD $KEYCLOAK_HOME/bin/kc.sh start-dev --log-level=$LOG_LEVEL > keycloak.log 2>&1 &
}

inputKeycloakUsername()
{
	echo ${grn}Input Keycloak Username : ${end}
	read KEYCLOAK_USERNAME
	if [ -z $KEYCLOAK_USERNAME ]; then
		echo ${red}No Keycloak Username input${end}
		inputKeycloakUsername
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