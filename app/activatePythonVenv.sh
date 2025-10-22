source ../setenv.sh

# ***** Activate Python Virtual environment
main()
{
    # Check if the directory exists
    echo Check if Python virtual environment ${blu}$PYTORCH_VIRTUAL_ENV${end} exists
    if [ -d "$PYTORCH_VIRTUAL_ENV" ]; then
        echo "Python virtual environment ${blu}$PYTORCH_VIRTUAL_ENV${end} exists, activating ..."
        activate
    else
        echo "Python virtual environment ${blu}$PYTORCH_VIRTUAL_ENV${end} does not exist, creating ..."
        source ./createPythonVenv.sh
        activate
    fi
}

# ***** Activate Python Virtual environment
activate()
{
    echo ${grn}To activate Python3 Virtual Environment, copy the following command on a shell${end}
    echo ${blu}source $PYTORCH_VIRTUAL_ENV/bin/activate${end}
}

# ***** MAIN EXECUTION
main