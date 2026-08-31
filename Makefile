# parser.py defaults to /opt/gluekube, the container layout, for both its input and its output.
# Pointing it at this checkout is what lets `make .env` work outside the container -- the rule
# could previously only ever write /opt/gluekube/.env, so the documented manual workflow could
# not bootstrap itself. python3, because plenty of distros no longer ship a `python` (#470).
.env:
	@test -f platform.json || { \
	  echo "No .env here, and no platform.json to build one from."; \
	  echo "Either write .env by hand (the readme lists every variable), or run this inside"; \
	  echo "the container, where AutoGlue drops platform.json next to the Makefile."; \
	  exit 1; \
	}
	GLUEKUBE_BASE_PATH=$(CURDIR) python3 parser.py

# This pair is what actually loads .env. Every target used to also carry
# `export $(grep -v '^#' .env | xargs);\` -- make expands $(grep ...) as a *make* function, not
# as shell, so it resolved to nothing and the line ran as a bare `export ;`. A bare export dumps
# the entire environment to stdout, which is how the credentials in #414 ended up pasted into a
# GitHub issue. Those eight lines are gone (#470).
#
# -include rather than include: an operator who exports the variables some other way should not
# be blocked by a missing file. `include` made every target die at this line instead.
-include .env
export

.PHONY: ping-servers check-connectivity setup sync rotate-master-nodes label-taint-nodes \
        rotate-certs-with-config upgrade-cluster migrate-local-path-provisioner

ping-servers: .env
	ansible all -i ansible/inventory/hosts.yaml -m ping
	@echo "Checking network connectivity between all nodes..."
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/check-network-connectivity.yaml

check-connectivity: .env
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

rotate-certs-with-config: .env
	@echo "Rotating certs with kubeadm config refresh..."
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/rotate-certs-with-config.yaml

upgrade-cluster: .env
	@echo "Upgrading the GlueKube cluster..."
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/upgrade-cluster.yaml

# One-off, once per cluster built before local-path-provisioner moved to its Helm chart. Not part
# of any other target: it deletes and recreates the running provisioner, so it stays something an
# operator runs on purpose. `setup` no longer depends on it -- install-local-path-provisioner.yaml
# skips the release and says so on an unmigrated cluster rather than aborting the play.
migrate-local-path-provisioner: .env
	@echo "Migrating local-path-provisioner to its Helm chart..."
	ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/migrate-local-path-provisioner.yaml
