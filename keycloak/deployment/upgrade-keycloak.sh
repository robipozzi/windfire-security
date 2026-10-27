#!/bin/bash
# Upgrade the Keycloak installed on raspberry01 (fresh installs: install-keycloak.sh)
cd "$(dirname "$0")" || exit 1
source ../../common.sh
export ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg
# Default target version: keycloak_version in raspberry/conf/raspberry-config.yml
DEFAULT_UPGRADE_VERSION=$(sed -n 's/^keycloak_version: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' raspberry/conf/raspberry-config.yml)

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo -e "${RED}ansible-playbook not found, install Ansible first (e.g. brew install ansible)${RESET}" >&2
    exit 1
fi

read -r -p "Keycloak version [${DEFAULT_UPGRADE_VERSION}]: " UPGRADE_VERSION
UPGRADE_VERSION=${UPGRADE_VERSION:-$DEFAULT_UPGRADE_VERSION}
if [[ ! "$UPGRADE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Invalid Keycloak version: $UPGRADE_VERSION (expected e.g. 26.8.1)${RESET}" >&2
    exit 1
fi

echo -e "${BLU}Upgrading Keycloak on raspberry01 (inventory group identitymanager) to ${UPGRADE_VERSION} ...${RESET}"
ansible-playbook -K raspberry/keycloak-upgrade.yaml -e keycloak_version="$UPGRADE_VERSION"
