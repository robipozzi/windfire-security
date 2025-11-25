###### Function section - START
printSelectEnvironment()
{
    ENVIRONMENT_SELECTION=$1
    if [[ -n "${ENVIRONMENT_SELECTION}" ]]; then
        echo 
    else
        echo ${blu}Select environment : ${end}
        echo "${blu}1. Development${end}"
        echo "${blu}2. Test${end}"
        echo "${blu}3. Production${end}"
        read ENVIRONMENT_SELECTION
    fi
	setEnvironment
}

setEnvironment()
{
	case $ENVIRONMENT_SELECTION in
		1)  ENVIRONMENT=dev
			;;
		2)  ENVIRONMENT=test
			;;
        3)  ENVIRONMENT=prod
            ;;
		*) 	printf "\n${red}No valid option selected${end}\n"
			printSelectEnvironment
			;;
	esac
}

getCredentials() {
    while true; do
        read -r -p "Enter username [${DEFAULT_USERNAME}]: " INPUT_USER
        if [[ -z "$INPUT_USER" ]]; then
            USERNAME="$DEFAULT_USERNAME"
        else
            USERNAME="$INPUT_USER"
        fi

        read -s -r -p "Enter password: " PASSWORD
        echo
        if [[ -z "$PASSWORD" ]]; then
            echo "Error: Password cannot be empty."
            continue
        fi

        read -r -p "Enter service [${DEFAULT_AUTH_SERVICE_TEST}]: " INPUT_SERVICE
        if [[ -z "$INPUT_SERVICE" ]]; then
            AUTH_SERVICE_TEST="$DEFAULT_AUTH_SERVICE_TEST"
        else
            AUTH_SERVICE_TEST="$INPUT_SERVICE"
        fi

        export USERNAME PASSWORD AUTH_SERVICE_TEST
        break
    done
}
###### Function section - END