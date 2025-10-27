ping-servers:
	ansible all -i ansible/inventory/hosts.yaml -m ping
setup:
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/setup-cluster.yaml
sync:
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/sync-resources.yaml
rotate-certs:
	echo "Rotating certificates for GlueKube..."
upgrade-cluster:
	echo "Upgrading the GlueKube cluster..."
patch-os:
	echo "Patching the operating system for GlueKube nodes..."
