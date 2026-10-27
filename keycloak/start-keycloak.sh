#!/bin/bash
source "$(dirname "$0")/../common.sh"
# ##### Variable section - START
SCRIPT=start-keycloak.sh
RUN_OPTION=$1
KEYCLOAK_PASSWORD=
DEFAULT_LOG_LEVEL=info
LOG_LEVEL=
KEYCLOAK_PORT=${KEYCLOAK_PORT:-$KEYCLOAK_SERVER_PORT}
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
	if [ -z "$RUN_OPTION" ]; then
		echo -e "${GREEN}Select Keycloak run platform : ${RESET}"
		echo -e "${GREEN}1. Server on Localhost (No TLS)${RESET}"
		echo -e "${GREEN}2. Server on Localhost (TLS enabled)${RESET}"
		echo -e "${GREEN}3. Docker${RESET}"
		read RUN_OPTION
	fi

	case $RUN_OPTION in
		1)  checkKeycloakInstall
			selectLogLevel
			bootstrapAdminOnFirstStart
			"$KEYCLOAK_HOME/bin/kc.sh" start-dev --log-level="$LOG_LEVEL"
			;;
		2)  checkKeycloakInstall
			checkTLSFiles
			selectLogLevel
			bootstrapAdminOnFirstStart
			"$KEYCLOAK_HOME/bin/kc.sh" start --http-enabled=false --https-certificate-file="$KEYCLOAK_CONF_TLS_DIR/$KEYCLOAK_CERT_NAME.crt" --https-certificate-key-file="$KEYCLOAK_CONF_TLS_DIR/$KEYCLOAK_CERT_NAME.key" --hostname=localhost --log-level="$LOG_LEVEL"
			;;
        3)  checkDocker
			if docker container inspect "$KEYCLOAK_CONTAINER_NAME" >/dev/null 2>&1; then
				startExistingContainer
			else
				selectLogLevel
				if [ -z "$KEYCLOAK_PASSWORD" ]; then
					inputKeycloakPassword
				fi
				# Admin credentials are passed by name only: docker reads the values from the environment, so they are not visible in ps
				export KC_BOOTSTRAP_ADMIN_USERNAME="$KEYCLOAK_USERNAME"
				export KC_BOOTSTRAP_ADMIN_PASSWORD="$KEYCLOAK_PASSWORD"
				echo -e "${BLU}Keycloak Admin Console will be available at http://localhost:$KEYCLOAK_PORT/admin${RESET}"
				docker run -p "$KEYCLOAK_PORT":8080 -e KC_BOOTSTRAP_ADMIN_USERNAME -e KC_BOOTSTRAP_ADMIN_PASSWORD --name "$KEYCLOAK_CONTAINER_NAME" "$KEYCLOAK_DOCKER_IMAGE:$KEYCLOAK_DOCKER_IMAGE_VERSION" start-dev --log-level="$LOG_LEVEL"
			fi
			;;
		*) 	printf "\n${RED}No valid option selected${RESET}\n"
			RUN_OPTION=
			selectPlatform
			;;
	esac
}

selectLogLevel()
{
	echo -e "${GREEN}Select Log level for Keycloak (default $DEFAULT_LOG_LEVEL) : ${RESET}"
	echo -e "${GREEN}1. Debug${RESET}"
	echo -e "${GREEN}2. Info${RESET}"
	echo -e "${GREEN}3. Warn${RESET}"
	echo -e "${GREEN}4. Error${RESET}"
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
		"") LOG_LEVEL=$DEFAULT_LOG_LEVEL
			;;
		*) 	printf "\n${RED}No valid option selected${RESET}\n"
			selectLogLevel
			;;
	esac
}

checkKeycloakInstall()
{
	# KEYCLOAK_HOME (common.sh) is installed by keycloak/deployment/install-keycloak.sh (option 2, localhost)
	if [ ! -x "$KEYCLOAK_HOME/bin/kc.sh" ]; then
		echo -e "${RED}Error: Keycloak not found in $KEYCLOAK_HOME${RESET}" >&2
		echo -e "${RED}Install it with keycloak/deployment/install-keycloak.sh 2, or set KEYCLOAK_VERSION in common.sh to an installed version${RESET}" >&2
		exit 1
	fi
	checkJava || exit 1
}

bootstrapAdminOnFirstStart()
{
	# On an empty database Keycloak creates a temporary admin from KC_BOOTSTRAP_ADMIN_* (ignored once data/ exists)
	if [ -d "$KEYCLOAK_HOME/data" ]; then
		return
	fi
	echo -e "${BLU}First start of $KEYCLOAK_HOME: creating temporary admin user $KEYCLOAK_USERNAME${RESET}"
	inputKeycloakPassword
	export KC_BOOTSTRAP_ADMIN_USERNAME="$KEYCLOAK_USERNAME"
	export KC_BOOTSTRAP_ADMIN_PASSWORD="$KEYCLOAK_PASSWORD"
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

checkDocker()
{
	if ! command -v docker >/dev/null 2>&1; then
		echo -e "${RED}Error: docker not found, install Docker Desktop first${RESET}" >&2
		exit 1
	fi
	if ! docker info >/dev/null 2>&1; then
		echo -e "${RED}Error: Docker daemon is not running, start Docker Desktop first${RESET}" >&2
		exit 1
	fi
}

startExistingContainer()
{
	local answer
	echo -e "${YELLOW}A container named $KEYCLOAK_CONTAINER_NAME already exists ($(docker container inspect -f '{{.Config.Image}}, {{.State.Status}}' "$KEYCLOAK_CONTAINER_NAME"))${RESET}"
	read -r -p "Start it? [Y/n] " answer
	if [[ "$answer" =~ ^[Nn] ]]; then
		echo -e "${RED}Not started: remove it with docker rm $KEYCLOAK_CONTAINER_NAME to create a new one${RESET}"
		exit 1
	fi
	docker start -a "$KEYCLOAK_CONTAINER_NAME"
}

inputKeycloakPassword()
{
	echo -e "${GREEN}Input Keycloak Password : ${RESET}"
	read -s KEYCLOAK_PASSWORD
	if [ -z "$KEYCLOAK_PASSWORD" ]; then
		echo -e "${RED}No Keycloak Password input${RESET}"
		inputKeycloakPassword
	fi
}
# ***** Function section - END

# ##############################################
# #################### MAIN ####################
# ##############################################
main
