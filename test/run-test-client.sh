source ../setenv.sh

# ***** Run Test script for Authentication Service
run()
{
    getCredentials
    USERNAME=$USERNAME \
    PASSWORD=$PASSWORD \
    SERVICE=$AUTH_SERVICE_TEST \
    python3 testClient.py
}

# ***** MAIN EXECUTION
run