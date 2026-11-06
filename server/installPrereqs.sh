source ../common.sh

# ***** Install Python prerequisites for Windfire Security server

# ===== INSTALL PYTHON MODULES PREREQUISITES FUNCTION =====
installPythonModules()
{
    pip3 install -r requirements.txt
}

# ===== EXECUTION =====
echo "Installing Python prerequisites..."
installPythonModules
echo -e "${GREEN}Python prerequisites installation complete.${RESET}"
echo