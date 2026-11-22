cd "$(dirname "$0")" || exit 1
source ../../common.sh
export ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg
runWithAnsibleSshKey ansible-playbook -K raspberry/keycloak-tls-deploy.yaml "$@"
