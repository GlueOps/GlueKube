.PHONY: init-env ping-servers
.ONESHELL:
init-env:
	@loadbalancer_apiserver=$$(jq -r '.cluster_load_balancer' /opt/gluekube/platform.json); \
	certificate_key=$$(jq -r '.certificate_key' /opt/gluekube/platform.json); \
	random_token=$$(jq -r '.random_token' /opt/gluekube/platform.json); \
	sed -i "s/loadbalancer_apiserver_placeholder/$${loadbalancer_apiserver}/" /opt/gluekube/ansible/inventory/group_vars/all.yaml; \
	sed -i "s/certificate_key_placeholder/$${certificate_key}/" /opt/gluekube/ansible/inventory/group_vars/masters.yaml; \
	sed -i "s/random_token_placeholder/$${random_token}/" /opt/gluekube/ansible/inventory/group_vars/masters.yaml; \
	python parser.py; \
	cat /opt/gluekube/ansible/inventory/group_vars/all.yaml
	cat /opt/gluekube/ansible/inventory/group_vars/masters.yaml

ping-servers: init-env
	ansible all -i ansible/inventory/hosts.yaml -m ping
setup: init-env
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/setup-cluster.yaml
sync: init-env
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/sync-resources.yaml
label-taint-nodes: init-env
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/setup-cluster.yaml --tags label_nodes
rotate-certs: init-env
	echo "Rotating certificates for GlueKube..."
upgrade-cluster: init-env
	echo "Upgrading the GlueKube cluster..."
patch-os: init-env
	echo "Patching the operating system for GlueKube nodes..."
