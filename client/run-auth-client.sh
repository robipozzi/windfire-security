source ../setenv.sh

# ***** Run Authentication client quick test
run()
{
    printSelectEnvironment
    getCredentials
    echo ${cyn}Running authentication client in environment : $ENVIRONMENT${end}
    ENVIRONMENT=$ENVIRONMENT \
    USERNAME=$USERNAME \
    PASSWORD=$PASSWORD \
    SERVICE=$AUTH_SERVICE_TEST \
    python3 authClient.py
}

# ***** MAIN EXECUTION
run