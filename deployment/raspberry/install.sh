eval "$(ssh-agent -s)"
ssh-add $HOME/.ssh/ansible_rsa
ansible-playbook windfire-security-install.yaml