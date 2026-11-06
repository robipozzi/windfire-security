source ../common.sh

# ***** Install Python prerequisites for Windfire Security tests

# ===== INSTALL PYTHON MODULES PREREQUISITES FUNCTION =====
installPythonModules()
{
    pip3 install -r requirements.txt
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