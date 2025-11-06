source ../setenv.sh

# ***** Run Test script for Authentication Service
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
run