source ../setenv.sh
source ../commons.sh

# ***** Run test client
main()
{
    echo ${blu}"###############################################"${end}
    echo ${blu}"############### Test client run ###############"${end}
    echo ${blu}"###############################################"${end}
    echo This script will run the following steps:
    echo    1. Create a Python Virtual Environment, if does not exist
    echo    2. Activate the Python Virtual Environment
    echo    3. Install Python prerequisites, if not already installed
    echo    4. Run test client
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
    python3 testClient.py
}

# ***** MAIN EXECUTION
main