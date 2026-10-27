#!/bin/bash
# Remove Keycloak from raspberry01: uninstall-keycloak.sh [-y]
cd "$(dirname "$0")" || exit 1
source ../../common.sh
export ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg
CONFIRM_HOST=raspberry01

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo -e "${RED}ansible-playbook not found, install Ansible first (e.g. brew install ansible)${RESET}" >&2
    exit 1
fi

if [[ "$1" != "-y" ]]; then
    echo -e "${RED}This permanently removes Keycloak from ${CONFIRM_HOST}: the keycloak systemd unit, /etc/keycloak (keycloak.conf, TLS key),${RESET}"
    echo -e "${RED}/opt/keycloak (every installed version, the realms database, upgrade backups and exports) and the keycloak user.${RESET}"
    read -r -p "Type ${CONFIRM_HOST} to confirm: " CONFIRMATION
    if [[ "$CONFIRMATION" != "$CONFIRM_HOST" ]]; then
        echo -e "${YELLOW}Not confirmed, nothing removed${RESET}"
        exit 1
    fi
fi

ansible-playbook -K raspberry/keycloak-uninstall.yaml
