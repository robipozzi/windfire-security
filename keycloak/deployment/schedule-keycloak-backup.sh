#!/bin/bash
# Install (or remove) the weekly Keycloak backup on raspberry01: schedule-keycloak-backup.sh [--remove] [-y]
# Settings (folder, archives kept, schedule) in raspberry/conf/keycloak-backup-config.yml
cd "$(dirname "$0")" || exit 1
source ../../common.sh
export ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg
CONFIG_FILE=raspberry/conf/keycloak-backup-config.yml
STATE=present
ASSUME_YES=false

usage()
{
    echo "Usage: $(basename "$0") [--remove] [-y] [-h]"
    echo "  --remove  Remove the timer, the service and the script (the archives on raspberry01 are kept)"
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
if [[ "$STATE" == present ]]; then
    echo -e "${YELLOW}raspberry01 will back up Keycloak $(readSetting scheduled_backup_on_calendar) to $(readSetting scheduled_backup_dir), keeping the newest $(readSetting scheduled_backup_keep) archives${RESET}"
    echo -e "${YELLOW}Keycloak is stopped during each export (about 1-2 minutes); the archives hold secrets in plain text, readable by root only${RESET}"
    PROMPT="Install the weekly Keycloak backup on raspberry01?"
else
    PROMPT="Remove the weekly Keycloak backup from raspberry01 (archives are kept)?"
fi
if [[ "$ASSUME_YES" != true ]]; then
    read -r -p "$PROMPT [y/N]: " CONFIRMATION
    if [[ ! "$CONFIRMATION" =~ ^[yY]$ ]]; then
        echo -e "${YELLOW}Not confirmed, nothing done${RESET}"
        exit 1
    fi
fi

# -K: sudo on raspberry01 requires the pi password
if ! runWithAnsibleSshKey ansible-playbook -K raspberry/keycloak-backup-schedule.yaml -e keycloak_backup_schedule_state="$STATE"; then
    echo -e "${RED}Failed, see the playbook output above${RESET}" >&2
    exit 1
fi
echo -e "${GREEN}Done${RESET}"
