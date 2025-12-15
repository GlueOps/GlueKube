.env:
	python parser.py

include .env
export


ping-servers: .env
	ansible all -i ansible/inventory/hosts.yaml -m ping

setup: .env
	export $(grep -v '^#' .env | xargs);\
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/setup-cluster.yaml
sync: .env
	export $(grep -v '^#' .env | xargs);\
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/sync-resources.yaml
label-taint-nodes: .env
	export $(grep -v '^#' .env | xargs);\
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/setup-cluster.yaml --tags label_nodes
rotate-certs: .env
	echo "Rotating certificates for GlueKube..."
upgrade-cluster: .env
	echo "Upgrading the GlueKube cluster..."
patch-os: .env
	echo "Patching the operating system for GlueKube nodes..."
