source ../setenv.sh

# ***** Install Python prerequisites for Google Calendar API
installPythonModules()
{
    pip3 install --upgrade \
                colorama==0.4.6 \
                requests==2.32.5\
                fastapi==0.104.1 \
                uvicorn[standard]==0.24.0 \
                httpx==0.28.1
}
installCustomPythonModules()
{
    pip3 install -e $HOME/dev/windfire-security
}

# ***** MAIN EXECUTION
echo "Installing Python prerequisites..."
installPythonModules
echo "Python prerequisites installation complete."
echo "Installing custom Python prerequisites..."
installCustomPythonModules
echo "Custom Python prerequisites installation complete."