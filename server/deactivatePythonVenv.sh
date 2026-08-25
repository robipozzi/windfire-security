source ../common.sh

# ***** Deactivate Python Virtual environment
main()
{
    # Check if the virtual environment is currently active in this shell
    echo -e "Check if Python virtual environment ${BLU}$PYTHON_SERVER_VIRTUAL_ENV${RESET} is active"
    if [ -n "$VIRTUAL_ENV" ] && [ "$(type -t deactivate)" = "function" ]; then
        echo -e "Python virtual environment ${BLU}$VIRTUAL_ENV${RESET} is active, deactivating ..."
        deactivate
        echo -e "${GREEN}Python Virtual Environment deactivated${RESET}"
    else
        echo -e "Python virtual environment ${BLU}$PYTHON_SERVER_VIRTUAL_ENV${RESET} is not active"
    fi
}

# ***** MAIN EXECUTION
main