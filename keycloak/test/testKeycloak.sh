source ../../setenv.sh

##### Variable section - START
SCRIPT=testKeycloak.sh
PLATFORM_OPTION=
FUNCTION=
DEFAULT_REALM_ID=windfire-restaurants
DEFAULT_REALM_USERNAME=windfire
DEFAULT_GRANT_TYPE=password
REALM_ID=
REALM_USERNAME=
REALM_PASSWORD=
GRANT_TYPE=
##### Variable section - END

##### Function section - START
main()
{
	printChoosePlatform
	
	inputRealmId
	inputRealmUsername
	inputRealmPassword
	inputGrantType
	
	echo ${grn}Running curl command to get OAuth2 Access Token ...${end}
	$FUNCTION
}

printChoosePlatform()
{
	echo ${grn}Select Keycloak platform to test: ${end}
    echo "${grn}1. Server on Localhost (No TLS)${end}"
	echo "${grn}2. Server on Localhost (TLS enabled with self signed certificate)${end}"
	read PLATFORM_OPTION
	setFunction
}

setFunction()
{
	case $PLATFORM_OPTION in
		1)  FUNCTION=curlNoTLS
			;;
		2)  FUNCTION=curlSelfSignedTLS
			;;
		*) 	printf "\n${red}No valid option selected${end}\n"
			printChooseFunction
			;;
	esac
}

curlNoTLS()
{
	echo ${blu}Running curl on HTTP endpoint${end}
	echo
	curl -X POST http://$KEYCLOAK_SERVER_ADDRESS:$KEYCLOAK_SERVER_PORT/realms/$REALM_ID/protocol/openid-connect/token \
		-H "Accept: application/json" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		-H "cache-control: no-cache" \
		-d "client_id=$REALM_ID&username=$REALM_USERNAME&password=$REALM_PASSWORD&grant_type=$GRANT_TYPE"
}

curlSelfSignedTLS()
{
	echo ${blu}Running curl on HTTPS endpoint${end}
	echo
	curl -X POST https://$KEYCLOAK_SERVER_ADDRESS:$KEYCLOAK_TLS_SERVER_PORT/realms/$REALM_ID/protocol/openid-connect/token \
	    --cacert $DEFAULT_TRUSTSTORE_DIR/$DEFAULT_CACERT_PEM \
		-H "Accept: application/json" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		-H "cache-control: no-cache" \
		-d "client_id=$REALM_ID&username=$REALM_USERNAME&password=$REALM_PASSWORD&grant_type=$GRANT_TYPE"
}

curlSelfSignedTLSwithNoCertverification()
{
	echo ${blu}Running curl on HTTPS endpoint, disabling TLS certificate verification${end}
	echo
	curl -X POST https://$KEYCLOAK_SERVER_ADDRESS:$KEYCLOAK_TLS_SERVER_PORT/realms/$REALM_ID/protocol/openid-connect/token \
		-H "Accept: application/json" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		-H "cache-control: no-cache" \
		-d "client_id=$REALM_ID&username=$REALM_USERNAME&password=$REALM_PASSWORD&grant_type=$GRANT_TYPE" \
		-k
}

inputRealmId()
{
	echo ${cyn}Input Realm ID - leaving blank will set Realm ID to ${end}${mag}$DEFAULT_REALM_ID : ${end}
	read REALM_ID
	if [ "$REALM_ID" == "" ]; then
		REALM_ID=$DEFAULT_REALM_ID
    fi
}

inputRealmUsername()
{
	echo ${cyn}Input Realm Username - leaving blank will set Realm Username to ${end}${mag}$DEFAULT_REALM_USERNAME : ${end}
	read REALM_USERNAME
	if [ "$REALM_USERNAME" == "" ]; then
		REALM_USERNAME=$DEFAULT_REALM_USERNAME
    fi
}

inputRealmPassword()
{
	echo ${cyn}Input Realm Password : ${end}
	read -s REALM_PASSWORD
	setRealmPassword
}

setRealmPassword()
{  
	if [ -z $REALM_PASSWORD ]; then
		echo ${red}No Realm Password input${end}
		inputRealmPassword
	fi
}

inputGrantType()
{
	echo ${cyn}Input Grant Type - leaving blank will set Grant Type to ${end}${mag}$DEFAULT_GRANT_TYPE : ${end}
	read GRANT_TYPE
	if [ "$GRANT_TYPE" == "" ]; then
		GRANT_TYPE=$DEFAULT_GRANT_TYPE
    fi
}
##### Function section - END

# ##############################################
# #################### MAIN ####################
# ##############################################
main