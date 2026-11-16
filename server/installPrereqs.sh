source ../common.sh

# ***** Install Python prerequisites for Windfire Security server

# ===== INSTALL PYTHON MODULES PREREQUISITES FUNCTION =====
# The stamp records which requirements.txt the venv was built from, so createPythonVenv.sh
# can reinstall when it changes (same approach as run-test-suite.sh)
installPythonModules()
{
    if pip3 install -r requirements.txt; then
        shasum -a 256 requirements.txt | cut -d' ' -f1 > "$VIRTUAL_ENV/.requirements.sha256"
    else
        echo -e "${RED}Python prerequisites installation failed${RESET}"
        rm -f "$VIRTUAL_ENV/.requirements.sha256"
    fi
}

# ===== EXECUTION =====
echo "Installing Python prerequisites..."
installPythonModules
echo -e "${GREEN}Python prerequisites installation complete.${RESET}"
echo