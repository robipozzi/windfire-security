source ../setenv.sh

# ***** Install Python prerequisites for Windfire Security tests

# ===== INSTALL PYTHON MODULES PREREQUISITES FUNCTION =====
installPythonModules()
{
    pip3 install --upgrade \
                colorama==0.4.6 \
                requests==2.32.5\
                fastapi==0.104.1 \
                uvicorn[standard]==0.24.0 \
                httpx==0.28.1
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