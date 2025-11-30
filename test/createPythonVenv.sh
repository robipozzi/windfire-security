source ../setenv.sh

# ***** Create Python Virtual environment
main()
{
    echo -e "${BLU}#########################################################${RESET}"
    echo -e "${BLU}########## Python Virtual Environment creation ##########${RESET}"
    echo -e "${BLU}#########################################################${RESET}"
    # Check if the directory exists
    echo -e "Check if Python virtual environment ${BLU}$PYTORCH_TEST_VIRTUAL_ENV${RESET} exists"
    if [ -d "$PYTORCH_TEST_VIRTUAL_ENV" ]; then
        echo -e "Python virtual environment ${BLU}$PYTORCH_TEST_VIRTUAL_ENV${RESET} exists, activating ..."
        echo
        activate
    else
        echo -e "${MAGENTA}Python virtual environment $PYTORCH_TEST_VIRTUAL_ENV does not exist, creating ...${RESET}"
        echo
        create
        echo
        activate
        echo
        installPrereqs
    fi
}

create()
{
    echo Creating Python Virtual Environment ...
    python3 -m venv $PYTORCH_TEST_VIRTUAL_ENV
    echo -e "${GREEN}Python Virtual Environment created${RESET}"
}

activate()
{
    source ./activatePythonVenv.sh
}

installPrereqs()
{
    source ./installPrereqs.sh
}

# ***** MAIN EXECUTION
main