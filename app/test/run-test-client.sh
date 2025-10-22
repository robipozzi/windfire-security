source ../../setenv.sh

getCredentials() {
    while true; do
        read -p "Enter username: " USERNAME
        if [[ -z "$USERNAME" ]]; then
            echo "Error: Username cannot be empty."
            continue
        fi
        read -s -p "Enter password: " PASSWORD
        echo
        if [[ -z "$PASSWORD" ]]; then
            echo "Error: Password cannot be empty."
            continue
        fi
        echo
        read -p "Enter service: " AUTH_SERVICE_TEST
        if [[ -z "$AUTH_SERVICE_TEST" ]]; then
            echo "Error: Username cannot be empty."
            continue
        fi
        export USERNAME
        export PASSWORD
        export AUTH_SERVICE_TEST
        break
    done
}

# ***** Run Test script for Authentication Service
run()
{
    #getCredentials
    USERNAME=$USERNAME \
    PASSWORD=$PASSWORD \
    SERVICE=$AUTH_SERVICE_TEST \
    python3 testClient.py
}

# ***** MAIN EXECUTION
run