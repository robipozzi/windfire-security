source ../setenv.sh

# ***** Activate Python Virtual environment
main()
{
    echo ${blu}"###########################################################"${end}
    echo ${blu}"########## Python Virtual Environment activation ##########"${end}
    echo ${blu}"###########################################################"${end}
    # Ensure the environment variable is set
    if [ -z "$PYTORCH_SERVER_VIRTUAL_ENV" ]; then
        echo "${mag}PYTORCH_SERVER_VIRTUAL_ENV${end} is not set"
        exit 1
    fi

    # Activate the virtual environment
    echo "${blu}PYTORCH_SERVER_VIRTUAL_ENV${end} is set to ${blu}$PYTORCH_SERVER_VIRTUAL_ENV${end}, proceeding to activate ..."
    echo Activating Python Virtual Environment with command ${blu}source $PYTORCH_SERVER_VIRTUAL_ENV/bin/activate${end}...
    source "$PYTORCH_SERVER_VIRTUAL_ENV/bin/activate"
    echo ${grn}Python Virtual Environment activated${end}
    echo 
    source ./installPrereqs.sh
}

# ***** MAIN EXECUTION
main