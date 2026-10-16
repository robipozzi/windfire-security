source ../../common.sh

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
	choosePlatform
	
	inputRealmId
	inputRealmUsername
	inputRealmPassword
	inputGrantType
	
	echo ${GREEN}Running curl command to get OAuth2 Access Token ...${RESET}
	$FUNCTION
}

choosePlatform()
{
	echo ${GREEN}Select Keycloak platform to test: ${RESET}
    echo "${GREEN}1. Server on Localhost (No TLS)${RESET}"
	echo "${GREEN}2. Server on Localhost (TLS enabled with self signed certificate)${RESET}"
	read PLATFORM_OPTION
	case $PLATFORM_OPTION in
		1)  FUNCTION=curlNoTLS
			;;
		2)  FUNCTION=curlSelfSignedTLS
			;;
		*) 	printf "\n${RED}No valid option selected${RESET}\n"
			choosePlatform
			;;
	esac
}

curlNoTLS()
{
	echo ${BLU}Running test on Keycloak HTTP endpoint${RESET}
	echo
	CURL="curl -X POST http://$KEYCLOAK_SERVER_ADDRESS:$KEYCLOAK_SERVER_PORT/realms/$REALM_ID/protocol/openid-connect/token"
	echo ${BLU}Running $CURL ...${RESET}
	echo
	$CURL \
		-H "Accept: application/json" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		-H "cache-control: no-cache" \
		-d "client_id=$REALM_ID&username=$REALM_USERNAME&password=$REALM_PASSWORD&grant_type=$GRANT_TYPE"
}

curlSelfSignedTLS()
{
	echo ${BLU}Running test on Keycloak HTTPS endpoint${RESET}
	echo
	CURL="curl -X POST https://$KEYCLOAK_SERVER_ADDRESS:$KEYCLOAK_TLS_SERVER_PORT/realms/$REALM_ID/protocol/openid-connect/token --cacert $KEYCLOAK_DEFAULT_TRUSTSTORE_DIR/$KEYCLOAK_ROOT_CA_CERTIFICATE"
	echo ${BLU}Running $CURL ...${RESET}
	echo
	$CURL \
		-H "Accept: application/json" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		-H "cache-control: no-cache" \
		-d "client_id=$REALM_ID&username=$REALM_USERNAME&password=$REALM_PASSWORD&grant_type=$GRANT_TYPE"
}

curlSelfSignedTLSwithNoCertverification()
{
	echo ${BLU}Running test on Keycloak HTTPS endpoint with no certificate verification${RESET}
	echo
	CURL="curl -X POST https://$KEYCLOAK_SERVER_ADDRESS:$KEYCLOAK_TLS_SERVER_PORT/realms/$REALM_ID/protocol/openid-connect/token"
	echo ${BLU}Running $CURL ...${RESET}
	echo
	$CURL \
		-H "Accept: application/json" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		-H "cache-control: no-cache" \
		-d "client_id=$REALM_ID&username=$REALM_USERNAME&password=$REALM_PASSWORD&grant_type=$GRANT_TYPE" \
		-k
}

inputRealmId()
{
	echo ${CYAN}Input Realm ID - leaving blank will set Realm ID to ${RESET}${MAGENTA}$DEFAULT_REALM_ID : ${RESET}
	read REALM_ID
	if [ "$REALM_ID" == "" ]; then
		REALM_ID=$DEFAULT_REALM_ID
    fi
}

inputRealmUsername()
{
	echo ${CYAN}Input Realm Username - leaving blank will set Realm Username to ${RESET}${MAGENTA}$DEFAULT_REALM_USERNAME : ${RESET}
	read REALM_USERNAME
	if [ "$REALM_USERNAME" == "" ]; then
		REALM_USERNAME=$DEFAULT_REALM_USERNAME
    fi
}

inputRealmPassword()
{
	echo ${CYAN}Input Realm Password : ${RESET}
	read -s REALM_PASSWORD
	if [ -z $REALM_PASSWORD ]; then
		echo ${RED}No Realm Password input${RESET}
		inputRealmPassword
	fi
}

inputGrantType()
{
	echo ${CYAN}Input Grant Type - leaving blank will set Grant Type to ${RESET}${MAGENTA}$DEFAULT_GRANT_TYPE : ${RESET}
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