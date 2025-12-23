#!/bin/bash
source ../common.sh

# ***** Deploy script for Windfire Security component *****

# ===== MAIN FUNCTION =====
main() {
    # Display header
    echo -e "${BOLD}${BLU}##########################################################################${RESET}"
    echo -e "${BOLD}${BLU}############### Windfire Security Service deploy procedure ###############${RESET}"
    echo -e "${BOLD}${BLU}##########################################################################${RESET}"
    echo
    
    # Parse arguments
    parseArgs $@

    # Start deployment
    deploy $@
}

parseArgs()
{
    echo -e "${BOLD}Parsing arguments...${RESET}"
    selectDeploymentPlatform $@
    echo -e "${BOLD}Selected platform: ${DEPLOY_PLATFORM}${RESET}"
}

deploy()
{ 
    setFunction
    $DEPLOY_FUNCTION
}

setFunction()
{
	case $DEPLOY_PLATFORM in
		raspberry) DEPLOY_FUNCTION="deployToRaspberry"
			;;
		*)  echo -e "${RED}No valid option selected${RESET}"
			selectDeploymentPlatform $@
			;;
	esac
}

deployToRaspberry()
{
	## Deploy Windfire Security component to remote Raspberry box
    echo -e "${BLU}Deploy Windfire Security component to Raspberry Pi ...${RESET}"
    eval "$(ssh-agent -s)"
    ssh-add $HOME/.ssh/ansible_rsa
    export ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg
    ansible-playbook raspberry/windfire-security-deploy.yaml
    echo -e "${BLU}Done${RESET}"
    echo 
}

# ===== EXECUTION =====
main $@