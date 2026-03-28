.env:
	python parser.py

include .env
export

ping-servers: .env
	ansible all -i ansible/inventory/hosts.yaml -m ping
	@echo "Checking network connectivity between all nodes..."
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/check-network-connectivity.yaml

setup: .env
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/setup-cluster.yaml

sync: .env
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/sync-resources.yaml

rotate-master-nodes: .env
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/rotate-master-nodes.yaml

label-taint-nodes: .env
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/setup-cluster.yaml --tags label_nodes

upgrade-cluster: .env
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/upgrade-cluster.yaml
