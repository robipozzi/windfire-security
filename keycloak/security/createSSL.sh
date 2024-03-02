source ../../setenv.sh

# ##### Variable section - START
SCRIPT=createSSL.sh
FUNCTION_CHOICE=
FUNCTION=
KEYSTORE=$1
VALIDITY=$2
KEYSTORE_PASSWORD=
# ##### Variable section - END

# ***** Function section - START
main()
{
    mkdir -p $DEFAULT_SSL_DIR
    $FUNCTION
}

printChooseFunction()
{
	echo ${grn}Choose function : ${end}
    echo "${grn}1. Generate server keystore${end}"
	read FUNCTION_CHOICE
	setFunctionChoice
}

setFunctionChoice()
{
	case $FUNCTION_CHOICE in
		1)  FUNCTION=createSSLKey
			;;
		*) 	printf "\n${red}No valid option selected${end}\n"
			printChooseFunction
			;;
	esac
}

createSSLKey()
{
    echo ${blu}*********************************${end}
    echo ${blu}***** Generate SSL keystore *****${end}
    echo ${blu}*********************************${end}
    echo

    echo ${blu}***** Creating a new keystore ...${end}
    if [ -z $KEYSTORE ]; then 
		inputKeystore
	fi
    if [ -z $KEYSTORE_PASSWORD ]; then 
		inputKeystorePassword
	fi
    if [ -z $VALIDITY ]; then 
		inputValidity
	fi
    
    CMD_RUN="keytool -keystore $DEFAULT_SSL_DIR/$KEYSTORE -alias $DEFAULT_KEYSTORE_ALIAS -validity $VALIDITY -genkeypair -keyalg RSA -keysize 2048 -keypass $KEYSTORE_PASSWORD -storepass $KEYSTORE_PASSWORD"

    echo ${cyn}Creating keystore using following command:${end} ${grn}$CMD_RUN${end}
    $CMD_RUN
    echo
}

inputKeystore()
{
    ###### Set keystore name
    if [ "$KEYSTORE" != "" ]; then
        echo Keystore is set to $KEYSTORE
    else
        echo ${grn}Enter keystore - leaving blank will set keystore to ${end}${mag}$DEFAULT_KEYSTORE : ${end}
        read KEYSTORE
        if [ "$KEYSTORE" == "" ]; then
            KEYSTORE=$DEFAULT_KEYSTORE
        fi
    fi
}

inputKeystorePassword()
{
    echo ${grn}Enter keystore password
	read -s KEYSTORE_PASSWORD
	setKeystorePassword
}

setKeystorePassword()
{  
	if [ -z $KEYSTORE_PASSWORD ]; then
		echo ${red}No Keystore password input${end}
		inputKeystorePassword
	fi
}

inputValidity()
{
    ###### Set validity days
    if [ "$VALIDITY" != "" ]; then
        echo Validity days are set to $VALIDITY
    else
        echo ${grn}Enter keystore validity days - leaving blank will set validaty days to ${end}${mag}$DEFAULT_VALIDITY : ${end}
        read VALIDITY
        if [ "$VALIDITY" == "" ]; then
            VALIDITY=$DEFAULT_VALIDITY
        fi
    fi
}
# ***** Function section - END

# ##############################################
# #################### MAIN ####################
# ##############################################
printChooseFunction
main