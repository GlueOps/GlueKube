FROM python:3.14-slim@sha256:caa9622dab9a2b41c988cda23de8d13d52c328df79d9c341c36ff2e81728a828

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV kubernetes_version="v1.34.5"
ENV kubernetes_package_version="1.34.5-1.1"
ENV calico_tigera_operator_version="v1.40.7"
ENV calico_chart_version="v3.31.4"
ENV ANSIBLE_ROLES_PATH=/opt/gluekube/ansible/roles
ENV ANSIBLE_LOG_PATH=/opt/gluekube/ansible/ansible.log
ENV ANSIBLE_HOST_KEY_CHECKING=False


# The pinned controller dependencies, copied before the rest of the tree so a change anywhere
# else in the repo does not invalidate the install layer.
COPY ansible/requirements.txt ansible/requirements.yml /tmp/gluekube-deps/

# Install system dependencies, install Python packages, and clean up in a single layer
RUN apt-get update && apt-get upgrade -y && \
    # Install build-essential for pip packages that need compilation
    apt-get install -y build-essential && \
    # ansible-core at the version in requirements.txt, NOT the batteries-included `ansible`
    # distribution this used to install unpinned. There are three machines that run these
    # playbooks -- this container, the CI runner, and the per-scenario bastion molecule builds --
    # and all three now install from the same two files. The old line pulled whatever collections
    # `ansible` happened to bundle, which meant the versions pinned in requirements.yml were the
    # one thing the container did not get.
    pip install --no-cache-dir -r /tmp/gluekube-deps/requirements.txt && \
    ansible-galaxy collection install -r /tmp/gluekube-deps/requirements.yml && \
    rm -rf /tmp/gluekube-deps && \
    apt-get install openssh-client -y && \
    # dnsutils supplies `dig`. master-node-rotation/update-dns-records.yaml shells out to it to
    # find the zone's authoritative nameservers and to confirm the ctrp record propagated before
    # the rotation drains and deletes the outgoing master -- and those tasks inherit
    # `delegate_to: localhost` from roles/master/tasks/rotate-master-nodes.yaml, so they run on
    # the Ansible controller, which in the hosted flow is THIS container and not the bastion.
    # (In a molecule run the controller IS a bastion, and molecule/common/bastion-prepare.yml
    # installs dnsutils there for exactly the same reason.)
    # Without dig the lookup returns nothing and the rotation deletes a master having verified
    # no propagation at all. CI never caught it because GitHub runners ship dig.
    apt-get install jq curl dnsutils -y

# Set working directory
WORKDIR /opt/gluekube

# Copy application files
COPY . /opt/gluekube

# Download Kubernetes GPG key at build time
RUN K8S_MINOR=$(echo $kubernetes_version | cut -d. -f1,2) && \
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" -o /opt/gluekube/kubernetes-release.key

# Define default command
CMD ["bash"]
