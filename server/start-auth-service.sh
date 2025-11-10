source ../setenv.sh

# ***** Start FastAPI server for Authentication Service
main()
{
    echo ${blu}#################################################################${end}
    echo ${blu}"############### Windfire Security Service startup ###############"${end}
    echo ${blu}#################################################################${end}
    echo This script will run the following steps:
    echo    1. Create a Python Virtual Environment, if does not exist
    echo    2. Activate the Python Virtual Environment
    echo    3. Install Python prerequisites, if not already installed
    echo    4. Start the Authentication Service FastAPI server
    echo 
    source ./createPythonVenv.sh
    run $1
}

run()
{
    printSelectEnvironment $1
    echo ${cyn}Running authentication service in environment : $ENVIRONMENT${end}
    ENVIRONMENT=$ENVIRONMENT \
    python3 authService.py
}

# ***** MAIN EXECUTION
main $1