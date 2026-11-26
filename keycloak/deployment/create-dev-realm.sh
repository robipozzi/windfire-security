#!/bin/bash
# Create (or remove) the windfire-dev realm on the raspberry01 Keycloak, for local development: create-dev-realm.sh [--remove] [-y]
# The realm is a copy of windfire (no users, new client secrets) whose Frontend URL is pinned to https://raspberry01:8443,
# so a UI running on localhost logs in without going through the Cloudflare Tunnel or Cloudflare Access.
# Settings in raspberry/conf/keycloak-dev-realm-config.yml. Runs on this computer through the Keycloak admin REST API
# (WINDFIRE_KC_ADMIN_USERNAME/PASSWORD, asked when unset, plus an OTP code): no SSH and no sudo on the Pi.
cd "$(dirname "$0")" || exit 1
source ../../common.sh
export ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg
# The playbook runs on the controller only: no pi sudo password needed
export ANSIBLE_BECOME_ASK_PASS=False
CONFIG_FILE=raspberry/conf/keycloak-dev-realm-config.yml
STATE=present
ASSUME_YES=false

usage()
{
    echo "Usage: $(basename "$0") [--remove] [-y] [-h]"
    echo "  --remove  Delete the dev realm (its users and client secrets are lost; the windfire realm is not touched)"
    echo "  -y        Do not ask for confirmation"
}

for arg in "$@"; do
    case "$arg" in
        --remove) STATE=absent ;;
        -y) ASSUME_YES=true ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo -e "${RED}ansible-playbook not found, install it first (e.g. brew install ansible)${RESET}" >&2
    exit 1
fi

readSetting() { sed -n "s/^$1: *\"\{0,1\}\([^\"]*\)\"\{0,1\} *$/\1/p" "$CONFIG_FILE"; }
DEV_REALM=$(readSetting keycloak_dev_realm)
if [[ "$STATE" == present ]]; then
    echo -e "${YELLOW}Realm ${DEV_REALM} will be created on raspberry01 from $(readSetting keycloak_dev_source_realm) (only read), if missing, with its Frontend URL pinned to the internal URL${RESET}"
    PROMPT="Create the ${DEV_REALM} realm on raspberry01?"
else
    echo -e "${RED}Realm ${DEV_REALM} will be deleted from raspberry01, with its users and client secrets${RESET}"
    PROMPT="Delete the ${DEV_REALM} realm from raspberry01?"
fi
if [[ "$ASSUME_YES" != true ]]; then
    read -r -p "$PROMPT [y/N] " CONFIRMATION
    if [[ ! "$CONFIRMATION" =~ ^[yY]$ ]]; then
        echo -e "${YELLOW}Not confirmed, nothing changed${RESET}"
        exit 1
    fi
fi

ansible-playbook raspberry/keycloak-dev-realm.yaml -e "keycloak_dev_realm_state=$STATE"
