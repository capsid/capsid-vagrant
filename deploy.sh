#ansible-playbook -v -i .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory --private-key=~/.vagrant.d/insecure_private_key -u vagrant global.yml --extra-vars "provisioning_platform=virtualbox"
#ansible-playbook -v -i .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory --private-key=~/.ssh/stuart-oicr-1.pem -u ubuntu global.yml --extra-vars "provisioning_platform=aws"
