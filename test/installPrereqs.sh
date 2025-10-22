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

# ***** MAIN EXECUTION
installPythonModules