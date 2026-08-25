source ../common.sh

# ***** Install Python prerequisites for Windfire Security server

# ===== INSTALL PYTHON MODULES PREREQUISITES FUNCTION =====
installPythonModules()
{
    pip3 install --upgrade \
                colorama==0.4.6 \
                fastapi==0.141.1 \
                uvicorn[standard]==0.52.4 \
                pydantic==2.13.4 \
                PyJWT==2.13.0 \
                requests==2.34.2 \
                cryptography==50.0.0 \
                python-dotenv==1.2.3
}

# ===== EXECUTION =====
echo "Installing Python prerequisites..."
installPythonModules
echo -e "${GREEN}Python prerequisites installation complete.${RESET}"
echo