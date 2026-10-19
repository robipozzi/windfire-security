#!/bin/bash
cd "$(dirname "$0")" || exit 1
source ../common.sh

# ***** Undeploy script for Windfire Security component *****

# ===== DEFAULT VALUES =====
ASSUME_YES=false

# ===== MAIN FUNCTION =====
main() {
    # Display header
    echo -e "${BOLD}${BLU}############################################################################${RESET}"
    echo -e "${BOLD}${BLU}############### Windfire Security Service undeploy procedure ###############${RESET}"
    echo -e "${BOLD}${BLU}############################################################################${RESET}"
    echo

    # Parse arguments
    parseArgs "$@"

    # Start undeployment
    undeploy
}

parseArgs()
{
    echo -e "${BOLD}Parsing arguments...${RESET}"
    PLATFORM_OPTION=
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                printHelp
                exit 0
                ;;
            -y|--yes)
                ASSUME_YES=true
                shift
                ;;
            -*)
                echo -e "${RED}Error: Unknown option '$1'${RESET}"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                PLATFORM_OPTION=$1
                shift
                ;;
        esac
    done
    selectDeploymentPlatform
    echo -e "${BOLD}Selected platform: ${DEPLOY_PLATFORM}${RESET}"
}

undeploy()
{
    setFunction
    $DEPLOY_FUNCTION
}

setFunction()
{
    while true; do
        case $DEPLOY_PLATFORM in
            raspberry) DEPLOY_FUNCTION="undeployFromRaspberry"
                return
                ;;
            *)  echo -e "${RED}No valid option selected${RESET}"
                PLATFORM_OPTION=""
                PLATFORM_SELECTED=false
                selectDeploymentPlatform || exit 1
                ;;
        esac
    done
}

confirmUndeploy()
{
    if [ "$ASSUME_YES" == true ]; then
        return
    fi
    local answer
    read -r -p "${YELLOW}This stops and removes the windfire-security service, its encrypted service configuration and application folder. Continue? [y/N]: ${END}" answer
    case $answer in
        y|Y|yes|YES) ;;
        *)  echo -e "${CYAN}Undeploy cancelled${RESET}"
            exit 0
            ;;
    esac
}

undeployFromRaspberry()
{
    ## Undeploy Windfire Security component from remote Raspberry box
    echo -e "${BLU}Undeploy Windfire Security component from Raspberry Pi ...${RESET}"
    confirmUndeploy
    eval "$(ssh-agent -s)" >/dev/null
    trap 'ssh-agent -k >/dev/null' EXIT
    ssh-add "$ANSIBLE_SSH_KEY" || { echo -e "${RED}Error: ssh-add $ANSIBLE_SSH_KEY failed${RESET}"; exit 1; }
    export ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg
    echo -e "${YELLOW}Ansible will ask for the BECOME password: the sudo password of user pi on the Raspberry${RESET}"
    if ansible-playbook raspberry/windfire-security-undeploy.yaml; then
        echo -e "${GREEN}Windfire Security removed from Raspberry Pi${RESET}"
        echo
    else
        echo -e "${RED}Undeployment failed: see Ansible output above${RESET}"
        exit 1
    fi
}

# ===== HELP FUNCTION =====
printHelp() {
    echo -e "${BOLD}╔═════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║    Windfire Security Service - Undeploy Script          ║${RESET}"
    echo -e "${BOLD}╚═════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo -e "${BOLD}DESCRIPTION:${RESET}"
    echo -e "Stops and removes the windfire-security systemd service, its encrypted service"
    echo -e "configuration and the application folder from the security_service Ansible host group."
    echo
    echo -e "${BOLD}USAGE:${RESET}"
    echo -e "    ./undeploy.sh [1] [-y]"
    echo
    echo -e "${BOLD}ARGUMENTS:${RESET}"
    echo -e "1                       Deployment platform: 1=Raspberry (prompted if omitted)"
    echo
    echo -e "${BOLD}OPTIONS:${RESET}"
    echo -e "-y, --yes               Do not ask for confirmation (the sudo password of user pi is still asked)"
    echo -e "-h, --help              Display this help message and exit"
    echo
    echo -e "${BOLD}EXIT CODES:${RESET}"
    echo -e "   0   Success, or cancelled by the operator"
    echo -e "   1   Invalid arguments or failed undeployment"
}

# ===== EXECUTION =====
main "$@"
