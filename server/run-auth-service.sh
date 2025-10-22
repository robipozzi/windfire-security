source ../setenv.sh

# ***** Run FastAPI server for Authentication Service
run()
{
    printSelectEnvironment
    echo ${cyn}Running authentication service in environment : $ENVIRONMENT${end}
    ENVIRONMENT=$ENVIRONMENT \
    KEYCLOAK_URL=$KEYCLOAK_URL \
    python3 authService.py
}

# ***** MAIN EXECUTION
run