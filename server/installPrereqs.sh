source ../setenv.sh
source ../commons.sh

# ***** Install Python prerequisites for Windfire Security server
installPythonModules()
{
    pip3 install --upgrade \
                colorama==0.4.6 \
                fastapi==0.104.1 \
                uvicorn[standard]==0.24.0 \
                pydantic==2.5.0 \
                PyJWT==2.8.0 \
                requests==2.32.5 \
                cryptography==41.0.0
}

# ***** MAIN EXECUTION
echo "Installing Python prerequisites..."
installPythonModules
echo ${grn}"Python prerequisites installation complete."${end}