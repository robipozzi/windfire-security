source ../common.sh

# ***** Install Python prerequisites for Windfire Security tests

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

# ===== INSTALL CUSTOME Windfire Security PYTHON MODULES PREREQUISITES FUNCTION =====
installCustomPythonModules()
{
    pip3 install -e $HOME/dev/windfire-security-client
}

# ===== EXECUTION =====
echo "Installing Python prerequisites..."
installPythonModules
echo "Python prerequisites installation complete."
echo ""
echo "Installing custom Python prerequisites..."
installCustomPythonModules
echo "Custom Python prerequisites installation complete."
echo