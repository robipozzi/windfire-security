source ../common.sh

# ***** Activate Python Virtual environment

# ===== MAIN FUNCTION =====
main()
{
    echo -e "${BLU}###########################################################${RESET}"
    echo -e "${BLU}########## Python Virtual Environment activation ##########${RESET}"
    echo -e "${BLU}###########################################################${RESET}"
    # Ensure the environment variable is set
    if [ -z "$PYTORCH_SERVER_VIRTUAL_ENV" ]; then
        echo -e "${MAGENTA}PYTORCH_SERVER_VIRTUAL_ENV${RESET} is not set"
        exit 1
    fi

    # Activate the virtual environment
    echo -e "${BLU}PYTORCH_SERVER_VIRTUAL_ENV${RESET} is set to ${BLU}$PYTORCH_SERVER_VIRTUAL_ENV${RESET}, proceeding to activate ..."
    echo -e "Activating Python Virtual Environment with command ${BLU}source $PYTORCH_SERVER_VIRTUAL_ENV/bin/activate${RESET}..."
    source "$PYTORCH_SERVER_VIRTUAL_ENV/bin/activate"
    echo -e "${GREEN}Python Virtual Environment activated${RESET}"
    echo
}

# ===== EXECUTION =====
main