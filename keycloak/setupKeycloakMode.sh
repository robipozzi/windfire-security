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

printChooseFunction()
{
	echo ${grn}Choose function : ${end}
    echo "${grn}1. Enable Keycloak TLS${end}"
    echo "${grn}2. Disable Keycloak TLS${end}"
	read FUNCTION_CHOICE
	setFunctionChoice
}

setFunctionChoice()
{
	case $FUNCTION_CHOICE in
		1)  FUNCTION=enableTLS
			;;
        2)  FUNCTION=disableTLS
            ;;
		*) 	printf "\n${red}No valid option selected${end}\n"
			printChooseFunction
			;;
	esac
}

enableTLS()
{
    echo ${blu}*******************************************${end}
    echo ${blu}***** Enable Keycloak to run with TLS *****${end}
    echo ${blu}*******************************************${end}
    echo

    echo ${blu}***** Copying $DEFAULT_KEYSTORE to $KEYCLOAK_HOME/conf ...${end}
    cp $DEFAULT_TLS_DIR/$DEFAULT_KEYSTORE $KEYCLOAK_HOME/conf
    echo
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
    echo ${blu}***** Keycloak is set to run with TLS disabled${end}
    echo
}
# ***** Function section - END

# ##############################################
# #################### MAIN ####################
# ##############################################
printChooseFunction
main