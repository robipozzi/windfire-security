#!/bin/bash
# Install Keycloak from scratch: install-keycloak.sh [1|2] [--side-by-side]
#   1. Raspberry (raspberry01, keycloak_version in raspberry/conf/raspberry-config.yml)
#   2. localhost (KEYCLOAK_VERSION/KEYCLOAK_HOME in common.sh)
# Each playbook stops gracefully if Keycloak is already installed and points to the upgrade procedure.
cd "$(dirname "$0")" || exit 1
source ../../common.sh
INSTALL_OPTION=$1
SIDE_BY_SIDE=false
if [[ "$2" == "--side-by-side" ]]; then
    SIDE_BY_SIDE=true
fi
DEFAULT_ADMIN_USERNAME=admin

selectInstallPlatform()
{
    if [[ -z "$INSTALL_OPTION" ]]; then
        echo -e "${BLU}Select where to install Keycloak :${RESET}"
        echo -e "${GREEN}1. Raspberry${RESET}"
        echo -e "${GREEN}2. localhost${RESET}"
        read -r INSTALL_OPTION
    fi
    case $INSTALL_OPTION in
        1)  installRaspberry
            ;;
        2)  installLocalhost
            ;;
        *)  echo -e "${RED}No valid option selected${RESET}"
            INSTALL_OPTION=
            selectInstallPlatform
            ;;
    esac
}

installRaspberry()
{
    local password_confirm
    # The temporary admin credentials reach the playbook through the environment only (never a command line)
    read -r -p "Temporary Keycloak admin username [${DEFAULT_ADMIN_USERNAME}]: " WINDFIRE_KC_ADMIN_USERNAME
    WINDFIRE_KC_ADMIN_USERNAME=${WINDFIRE_KC_ADMIN_USERNAME:-$DEFAULT_ADMIN_USERNAME}
    while true; do
        read -r -s -p "Temporary Keycloak admin password: " WINDFIRE_KC_ADMIN_PASSWORD
        echo
        read -r -s -p "Confirm password: " password_confirm
        echo
        if [[ -z "$WINDFIRE_KC_ADMIN_PASSWORD" ]]; then
            echo -e "${RED}Password cannot be empty${RESET}"
        elif [[ "$WINDFIRE_KC_ADMIN_PASSWORD" != "$password_confirm" ]]; then
            echo -e "${RED}Passwords do not match${RESET}"
        else
            break
        fi
    done
    export WINDFIRE_KC_ADMIN_USERNAME WINDFIRE_KC_ADMIN_PASSWORD
    echo -e "${BLU}Installing Keycloak on raspberry01 (stops if Keycloak is already installed) ...${RESET}"
    ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg ansible-playbook -K raspberry/keycloak-install.yaml
}

installLocalhost()
{
    echo -e "${BLU}Installing Keycloak ${KEYCLOAK_VERSION} in ${KEYCLOAK_HOME} (stops if Keycloak is already installed) ...${RESET}"
    ANSIBLE_CONFIG=$PWD/localhost/ansible.cfg ansible-playbook localhost/keycloak-install.yaml \
        -e keycloak_version="$KEYCLOAK_VERSION" -e keycloak_home="$KEYCLOAK_HOME" -e keycloak_side_by_side="$SIDE_BY_SIDE"
}

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo -e "${RED}ansible-playbook not found, install Ansible first (e.g. brew install ansible)${RESET}" >&2
    exit 1
fi
selectInstallPlatform
