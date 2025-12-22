source ../common.sh

# ***** Create Python Virtual environment

# ===== MAIN FUNCTION =====
main()
{
    echo -e "${BLU}#########################################################${RESET}"
    echo -e "${BLU}########## Python Virtual Environment creation ##########${RESET}"
    echo -e "${BLU}#########################################################${RESET}"
    # Check if the directory exists
    echo -e "Check if Python virtual environment ${BLU}$PYTORCH_SERVER_VIRTUAL_ENV${RESET} exists"
    if [ -d "$PYTORCH_SERVER_VIRTUAL_ENV" ]; then
        echo -e "Python virtual environment ${BLU}$PYTORCH_SERVER_VIRTUAL_ENV${RESET} exists, activating ..."
        echo
        activate
    else
        echo -e "${MAGENTA}Python virtual environment $PYTORCH_SERVER_VIRTUAL_ENV does not exist, creating ...${RESET}"
        echo
        create
        echo
        activate
        echo
        installPrereqs
    fi
}

# ===== CREATE PYTHON VIRTUAL ENV FUNCTION =====
create()
{
    echo Creating Python Virtual Environment ...
    python3 -m venv $PYTORCH_SERVER_VIRTUAL_ENV
    echo -e "${GREEN}Python Virtual Environment created${RESET}"
}

# ===== ACTIVATE PYTHON VIRTUAL ENV FUNCTION =====
activate()
{
    source ./activatePythonVenv.sh
}

# ===== INSTALL PYTHON PREREQUISITE MODULES FUNCTION =====
installPrereqs()
{
    source ./installPrereqs.sh
}

# ===== EXECUTION =====
main