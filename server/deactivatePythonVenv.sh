source ../setenv.sh

# ***** Deactivate Python Virtual environment
main()
{
    # Check if the directory exists
    echo -e "Check if Python virtual environment ${BLU}$PYTORCH_SERVER_VIRTUAL_ENV${RESET} exists"
    if [ -d "$PYTORCH_SERVER_VIRTUAL_ENV" ]; then
        echo - "Python virtual environment ${BLU}$PYTORCH_SERVER_VIRTUAL_ENV${RESET} exists, deactivating ..."
        deactivate
    else
        echo -e "Python virtual environment ${BLU}$PYTORCH_SERVER_VIRTUAL_ENV${RESET} does not exist"
    fi
}

# ***** Deactivate Python Virtual environment
deactivate()
{
    echo -e "${GREEN}To deactivate Python3 Virtual Environment, copy the following command on a shell${RESET}"
    echo -e "${BLU}deactivate${RESET}"
}

# ***** MAIN EXECUTION
main