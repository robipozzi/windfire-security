#!/bin/bash

# ***** Start FastAPI server for Authentication Service

source ../setenv.sh
source ../commons.sh

# ===== DEFAULT VALUES =====
ENVIRONMENT=""
LOG_LEVEL="INFO"

# ===== MAIN FUNCTION =====
main() {
    # Parse command-line arguments
    parse_args "$@"
    
    # Validate arguments
    validate_environment
    
    # Display header
    echo -e "${BOLD}${BLU}#################################################################${RESET}"
    echo -e "${BOLD}${BLU}############### Windfire Security Service Startup ###############${RESET}"
    echo -e "${BOLD}${BLU}#################################################################${RESET}"
    echo
    
    # Create and activate virtual environment
    source ./createPythonVenv.sh

    # Run the authentication server
    run_server
}

# ===== SERVER RUN FUNCTION =====
run_server() {
    printSelectEnvironment "$ENVIRONMENT"

    # Show configuration
    display_config

    echo -e "${YELLOW}Running authentication server in environment: $ENVIRONMENT${RESET}"
    
    # Build Python command with optional flags
    local python_cmd="python3 authServer.py --port $PORT"

    if [ -z "${PORT}" ]; then
        echo -e "${YELLOW}PORT is not set or is empty.${RESET}"
        python_cmd="python3 authServer.py"
    fi

    if [ "$VERBOSE" = true ]; then
        LOG_LEVEL="DEBUG"
    fi
    
    echo -e "${YELLOW}Starting server with: ENVIRONMENT="$ENVIRONMENT" LOG_LEVEL="$LOG_LEVEL" $python_cmd${RESET}"
    # Set environment, log level and run
    ENVIRONMENT="$ENVIRONMENT" LOG_LEVEL="$LOG_LEVEL" eval "$python_cmd"
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
            -v|--verbose)
                VERBOSE=true
                shift
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
    echo -e "  Environment:    ${YELLOW}$ENVIRONMENT${RESET}"
    echo -e "  Port:           ${YELLOW}$PORT${RESET}"
    echo -e "  Verbose:        ${YELLOW}$([ "$VERBOSE" = true ] && echo 'Enabled' || echo 'Disabled')${RESET}"
    echo
}

# ===== HELP FUNCTION =====
print_help() {
    # Display help information
    echo -e "${BOLD}========================================================${RESET}"
    echo -e "${BOLD}Windfire Security - Authentication Server Startup${RESET}"
    echo -e "${BOLD}========================================================${RESET}"
    echo
    echo -e "${BOLD}DESCRIPTION:${RESET}"
    echo -e "    This script initializes and starts the FastAPI Authentication"
    echo -e "    Service with Python virtual environment management, running the following steps:"
    echo
    echo -e "    1. Create a Python Virtual Environment (if not present)"
    echo -e "    2. Activate the Python Virtual Environment"
    echo -e "    3. Install Python prerequisites (if not already installed)"
    echo -e "    4. Start the Authentication Service FastAPI server"
    echo
    echo -e "${BOLD}USAGE:${RESET}"
    echo -e "    ./start-auth-server.sh [OPTIONS]"
    echo
    echo -e "${BOLD}OPTIONS:${RESET}"
    echo -e "    -e, --environment ENV      Set environment (dev, staging, prod)"
    echo -e "                               Default: dev"
    echo
    echo -e "    -p, --port PORT            Specify server port (1-65535)"
    echo -e "                               Default: 8000"
    echo
    echo -e "    -v, --verbose              Enable debug logging"
    echo -e "                               Default: disabled"
    echo
    echo -e "    -h, --help                 Display this help message and exit"
    echo
    echo -e "${BOLD}EXAMPLES:${RESET}"
    echo -e "    # Run with default settings (dev environment, localhost:8000)"
    echo -e "    ./start-auth-server.sh"
    echo
    echo -e "    # Run in production environment on custom port"
    echo -e "    ./start-auth-server.sh -e prod -p 9000"
    echo
    echo -e "    # Run with verbose logging for debug purposes"
    echo -e "    ./start-auth-server.sh -v"
    echo
    echo -e "    # Run in staging with multiple options"
    echo -e "    ./start-auth-server.sh --environment staging --port 8001 --verbose"
    echo
    echo -e "${BOLD}STARTUP STEPS:${RESET}"
    echo -e "    1. Create a Python Virtual Environment (if it doesn't exist)"
    echo -e "    2. Activate the Python Virtual Environment"
    echo -e "    3. Install Python prerequisites (if not already installed)"
    echo -e "    4. Start the Authentication Service FastAPI server"
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
