#!/bin/bash

# ***** Run test client

source ../setenv.sh
source ../commons.sh

# ===== DEFAULT VALUES =====
ENVIRONMENT="prod"
DEFAULT_PORT=8001

# ===== MAIN FUNCTION =====
main()
{
    # Display header
    echo -e "${BOLD}${BLU}###################################################################${RESET}"
    echo -e "${BOLD}${BLU}############### Windfire Security - Test client run ###############${RESET}"
    echo -e "${BOLD}${BLU}###################################################################${RESET}"
    echo

    # Parse command-line arguments
    parse_args "$@"
    
    # Validate arguments
    validate_environment
    
    # Create and activate virtual environment
    source ./createPythonVenv.sh
    
    run
}

# ===== TEST CLIENT RUN FUNCTION =====
run()
{
    getCredentials

    echo -e "${YELLOW}Running test authenticating to Windfire Security server in environment: $ENVIRONMENT${RESET}"

    # Build Python command with optional flags
    local python_cmd="python3 testClient.py"

    if [ -z "${PORT}" ]; then
        echo -e "${YELLOW}PORT is not set or is empty, calling Test server on default $DEFAULT_PORT${RESET}"
        PORT=$DEFAULT_PORT
    fi

    # Show configuration
    display_config

    # Running Test client
    echo -e "${YELLOW}Running test client with: ENVIRONMENT=$ENVIRONMENT PORT=$PORT USERNAME=$USERNAME PASSWORD={***} SERVICE=$AUTH_SERVICE_TEST VERIFY_SSL_CERTS=$VERIFY_SSL_CERTS python3 testClient.py${RESET}"
    
    ENVIRONMENT=$ENVIRONMENT \
    PORT=$PORT \
    USERNAME=$USERNAME \
    PASSWORD=$PASSWORD \
    SERVICE=$AUTH_SERVICE_TEST \
    VERIFY_SSL_CERTS=$VERIFY_SSL_CERTS \
    python3 testClient.py
}

# ===== ARGUMENT PARSING FUNCTION =====
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -p|--port)
                PORT="$2"
                shift 2
                ;;
            -h|--help)
                print_help
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option '$1'${RESET}"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# ===== VALIDATION FUNCTION =====
validate_environment() {
    if [ -z "${ENVIRONMENT}" ]; then
        echo -e "${YELLOW}ENVIRONMENT is not set or is empty.${RESET}"
        return
    fi

    case "$ENVIRONMENT" in
        dev|staging|prod)
            return 0
            ;;
        *)
            echo -e "${RED}Error: Invalid environment '$ENVIRONMENT'${RESET}"
            echo "Valid options: dev, staging, prod"
            exit 1
            ;;
    esac
}

# ===== CONFIGURATION DISPLAY FUNCTION =====
display_config() {
    echo -e "${BOLD}${GREEN}Configuration Summary:${RESET}"
    echo -e "  Environment:         ${YELLOW}$ENVIRONMENT${RESET}"
    echo -e "  Test server port:    ${YELLOW}$PORT${RESET}"
    echo
}

# ===== HELP FUNCTION =====
print_help() {
    # Display help information
    echo -e "${BOLD}===================================${RESET}"
    echo -e "${BOLD}Windfire Security - Test client run${RESET}"
    echo -e "${BOLD}===================================${RESET}"
    echo
    
    echo -e "${BOLD}DESCRIPTION:${RESET}"
    echo -e "    This script runs a test for Windfire Security Authentication services"
    echo -e "    1. Authenticates to the Windfire Security server and gets a token"
    echo -e "    2. Calls a protected API on a Test Server using the token"
    echo
    echo -e "    Service with Python virtual environment management, running the following steps:"
    echo -e "    1. Create a Python Virtual Environment, if does not exist"
    echo -e "    2. Activate the Python Virtual Environment"
    echo -e "    3. Install Python prerequisites, if not already installed"
    echo -e "    4. Run test client"
    echo 
    echo -e "${BOLD}USAGE:${RESET}"
    echo -e "    ./run-test-client.sh [OPTIONS]"
    echo
    echo -e "${BOLD}OPTIONS:${RESET}"
    echo -e "    -e, --environment ENV      Set environment for Windfire Security server to authenticate and validate"
    echo -e "                               Available environment: dev, staging, prod"
    echo -e "                               Default: prod"
    echo
    echo -e "    -p, --port PORT            Specify Test server port (1-65535)"
    echo -e "                               Default: 8001"
    echo
    echo -e "    -h, --help                 Display this help message and exit"
    echo
    echo -e "${BOLD}EXAMPLES:${RESET}"
    echo -e "    # Run with default settings (prod environment, Windfire Security server on https://raspberry01:8443)"
    echo -e "    ./run-test-client.sh"
    echo
    echo -e "    # Run and authenticate to Windfire Security development environment"
    echo -e "    ./run-test-client.sh -e dev"
    echo
    echo -e "    # Run test with Test server running on a non default port and" 
    echo -e "    # authenticate to Windfire Security development environment"
    echo -e "    ./run-test-client.sh -e dev -p 8112"
    echo
    echo -e "${BOLD}STARTUP STEPS:${RESET}"
    echo -e "    This script will run the following steps:"
    echo -e "    1. Create a Python Virtual Environment, if does not exist"
    echo -e "    2. Activate the Python Virtual Environment"
    echo -e "    3. Install Python prerequisites, if not already installed"
    echo -e "    4. Run test client"
    echo 
    echo -e "${BOLD}TROUBLESHOOTING:${RESET}"
    echo -e "    • Permission denied: Run 'chmod +x start-auth-server.sh'"
    echo -e "    • Module not found: Ensure createPythonVenv.sh is in the current directory"
    echo
    echo -e "${BOLD}========================================================${RESET}"
}

# ===== EXECUTION =====
main "$@"