#!/bin/bash

# ***** Start Test server

source ../setenv.sh
source ../commons.sh

# ===== DEFAULT VALUES =====
DEFAULT_PORT=8001

# ===== MAIN FUNCTION =====
main()
{
    # Parse command-line arguments
    parse_args "$@"
    
    # Display header
    echo -e "${BLU}#######################################################################${RESET}"
    echo -e "${BLU}############### Windfire Security - Test server startup ###############${RESET}"
    echo -e "${BLU}#######################################################################${RESET}"
    echo 
    
    # Create and activate virtual environment
    source ./createPythonVenv.sh

    run
}

run()
{
    getCredentials

    echo -e "${YELLOW}Running Test server${RESET}"
    
    # Build Python command with optional flags
    local python_cmd="python3 testServer.py"

    if [ -z "${PORT}" ]; then
        echo -e "${YELLOW}PORT is not set or is empty, running with default $DEFAULT_PORT${RESET}"
        PORT=$DEFAULT_PORT
    fi

    # Show configuration
    display_config

    # Start Test server
    echo -e "${YELLOW}Starting server with: USERNAME=$USERNAME PASSWORD={***} SERVICE=$AUTH_SERVICE_TEST VERIFY_SSL_CERTS=$VERIFY_SSL_CERTS PORT=$PORT $python_cmd${RESET}"
    
    USERNAME=$USERNAME \
    PASSWORD=$PASSWORD \
    SERVICE=$AUTH_SERVICE_TEST \
    VERIFY_SSL_CERTS=$VERIFY_SSL_CERTS \
    PORT=$PORT \
    $python_cmd
}

# ===== ARGUMENT PARSING FUNCTION =====
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
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

# ===== VALIDATION FUNCTION (### NOT USED ###) =====
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
    echo -e "  Port:           ${YELLOW}$PORT${RESET}"
    echo
}

# ===== HELP FUNCTION =====
print_help() {
    # Display help information
    echo -e "${BOLD}=======================================${RESET}"
    echo -e "${BOLD}Windfire Security - Test server startup${RESET}"
    echo -e "${BOLD}=======================================${RESET}"
    echo
    
    echo -e "${BOLD}DESCRIPTION:${RESET}"
    echo -e "    This script runs a test server that exposes an endpoint secured through"
    echo -e "    Windfire Security Authentication services"
    echo
    echo -e "    Service with Python virtual environment management, running the following steps:"
    echo -e "    1. Create a Python Virtual Environment, if does not exist"
    echo -e "    2. Activate the Python Virtual Environment"
    echo -e "    3. Install Python prerequisites, if not already installed"
    echo -e "    4. Startup Test server"
    echo 
    echo -e "${BOLD}USAGE:${RESET}"
    echo -e "    ./start-test-server.sh [OPTIONS]"
    echo
    echo -e "${BOLD}OPTIONS:${RESET}"
    echo -e "    -p, --port PORT            Specify server port (1-65535)"
    echo -e "                               Default: 8001"
    echo
    echo -e "    -h, --help                 Display this help message and exit"
    echo
    echo -e "${BOLD}EXAMPLES:${RESET}"
    echo -e "    # Run with default settings (port 8001)"
    echo -e "    ./start-test-server.sh"
    echo
    echo -e "    # Run on a custom port"
    echo -e "    ./start-test-server.sh -p 8104"
    echo
    echo -e "${BOLD}STARTUP STEPS:${RESET}"
    echo -e "    This script will run the following steps:"
    echo -e "    1. Create a Python Virtual Environment, if does not exist"
    echo -e "    2. Activate the Python Virtual Environment"
    echo -e "    3. Install Python prerequisites, if not already installed"
    echo -e "    4. Startup Test server"
    echo 
    echo -e "${BOLD}TROUBLESHOOTING:${RESET}"
    echo -e "    • Port already in use: Use -p to specify a different port"
    echo -e "    • Permission denied: Run 'chmod +x start-auth-server.sh'"
    echo -e "    • Module not found: Ensure createPythonVenv.sh is in the current directory"
    echo
    echo -e "${BOLD}========================================================${RESET}"
}

# ===== EXECUTION =====
main "$@"