source ../setenv.sh

# ***** Deactivate Python Virtual environment
main()
{
    # Check if the directory exists
    echo Check if Python virtual environment ${blu}$PYTORCH_VIRTUAL_ENV${end} exists
    if [ -d "$PYTORCH_VIRTUAL_ENV" ]; then
        echo "Python virtual environment ${blu}$PYTORCH_VIRTUAL_ENV${end} exists, deactivating ..."
        deactivate
    else
        echo "Python virtual environment ${blu}$PYTORCH_VIRTUAL_ENV${end} does not exist"
    fi
}

# ***** Deactivate Python Virtual environment
deactivate()
{
    echo ${grn}To deactivate Python3 Virtual Environment, copy the following command on a shell${end}
    echo ${blu}deactivate${end}
}

# ***** MAIN EXECUTION
main