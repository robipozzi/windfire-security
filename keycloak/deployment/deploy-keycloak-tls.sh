cd "$(dirname "$0")" || exit 1
export ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg
ansible-playbook -K raspberry/keycloak-tls-deploy.yaml
