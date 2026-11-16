source ../common.sh

# ***** Create Python Virtual environment

# ===== MAIN FUNCTION =====
main()
{
    echo -e "${BLU}#########################################################${RESET}"
    echo -e "${BLU}########## Python Virtual Environment creation ##########${RESET}"
    echo -e "${BLU}#########################################################${RESET}"
    # Check if the directory exists
    echo -e "Check if Python virtual environment ${BLU}$PYTHON_SERVER_VIRTUAL_ENV${RESET} exists"
    if [ -d "$PYTHON_SERVER_VIRTUAL_ENV" ]; then
        echo -e "Python virtual environment ${BLU}$PYTHON_SERVER_VIRTUAL_ENV${RESET} exists, activating ..."
        echo
        activate
        if requirementsChanged; then
            echo -e "${MAGENTA}requirements.txt changed since the last install, installing ...${RESET}"
            echo
            installPrereqs
        fi
    else
        echo -e "${MAGENTA}Python virtual environment $PYTHON_SERVER_VIRTUAL_ENV does not exist, creating ...${RESET}"
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
    python3 -m venv $PYTHON_SERVER_VIRTUAL_ENV
    echo -e "${GREEN}Python Virtual Environment created${RESET}"
}

# ===== ACTIVATE PYTHON VIRTUAL ENV FUNCTION =====
activate()
{
    source ./activatePythonVenv.sh
}

# ===== REQUIREMENTS CHANGE CHECK FUNCTION =====
# True when requirements.txt differs from the one recorded by installPrereqs.sh (or none is recorded)
requirementsChanged()
{
    local stamp
    stamp=$(shasum -a 256 requirements.txt | cut -d' ' -f1)
    [ "$(cat "$VIRTUAL_ENV/.requirements.sha256" 2>/dev/null)" != "$stamp" ]
}

# ===== INSTALL PYTHON PREREQUISITE MODULES FUNCTION =====
installPrereqs()
{
    source ./installPrereqs.sh
}

# ===== EXECUTION =====
main