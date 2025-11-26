source ../setenv.sh
source ../commons.sh

# ***** Start Test server
main()
{
    echo ${blu}"###################################################"${end}
    echo ${blu}"############### Test server startup ###############"${end}
    echo ${blu}"###################################################"${end}
    echo This script will run the following steps:
    echo    1. Create a Python Virtual Environment, if does not exist
    echo    2. Activate the Python Virtual Environment
    echo    3. Install Python prerequisites, if not already installed
    echo    4. Start the Test server
    echo 
    source ./createPythonVenv.sh
    run
}

run()
{
    getCredentials
    USERNAME=$USERNAME \
    PASSWORD=$PASSWORD \
    SERVICE=$AUTH_SERVICE_TEST \
    VERIFY_SSL_CERTS=$VERIFY_SSL_CERTS \
    python3 testServer.py
}

# ***** MAIN EXECUTION
main