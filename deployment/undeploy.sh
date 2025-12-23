#!/bin/bash
source ../common.sh

# ***** Undeploy script for Windfire Security component *****

# ===== MAIN FUNCTION =====
main() {
    # Display header
    echo -e "${BOLD}${BLU}############################################################################${RESET}"
    echo -e "${BOLD}${BLU}############### Windfire Security Service undeploy procedure ###############${RESET}"
    echo -e "${BOLD}${BLU}############################################################################${RESET}"
    echo
    
    # Parse arguments
    parseArgs $@

    # Start undeployment
    undeploy $@
}

parseArgs()
{
    echo -e "${BOLD}Parsing arguments...${RESET}"
    selectDeploymentPlatform $@
    echo -e "${BOLD}Selected platform: ${DEPLOY_PLATFORM}${RESET}"
}

undeploy()
{ 
    setFunction
    $DEPLOY_FUNCTION
}

setFunction()
{
	case $DEPLOY_PLATFORM in
		raspberry) DEPLOY_FUNCTION="undeployFromRaspberry"
			;;
		*)  echo -e "${RED}No valid option selected${RESET}"
			selectDeploymentPlatform $@
			;;
	esac
}

undeployFromRaspberry()
{
	## Undeploy Windfire Security component from remote Raspberry box
    echo -e "${BLU}Undeploy Windfire Security component from Raspberry Pi ...${RESET}"
    eval "$(ssh-agent -s)"
    ssh-add $HOME/.ssh/ansible_rsa
    export ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg
    ansible-playbook raspberry/windfire-security-undeploy.yaml
    echo -e "${BLU}Done${RESET}"
    echo
}

# ===== EXECUTION =====
main $@