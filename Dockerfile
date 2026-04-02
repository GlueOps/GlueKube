FROM python:3.14-slim@sha256:fb83750094b46fd6b8adaa80f66e2302ecbe45d513f6cece637a841e1025b4ca

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV kubernetes_version="v1.34.5"
ENV kubernetes_package_version="1.34.5-1.1"
ENV calico_tigera_operator_version="v1.40.7"
ENV calico_chart_version="v3.31.4"
ENV ANSIBLE_ROLES_PATH=/opt/gluekube/ansible/roles
ENV ANSIBLE_LOG_PATH=/opt/gluekube/ansible/ansible.log
ENV ANSIBLE_HOST_KEY_CHECKING=False


# Install system dependencies, install Python packages, and clean up in a single layer
RUN apt-get update && apt-get upgrade -y && \
    # Install build-essential for pip packages that need compilation
    apt-get install -y build-essential && \
    # Install ansible and jmespath using pip for Python 3.12
    # Use --no-cache-dir to keep the image slim
    pip install --no-cache-dir ansible jmespath && \
    apt-get install openssh-client -y && \
    apt-get install jq curl -y

# Set working directory
WORKDIR /opt/gluekube

# Copy application files
COPY . /opt/gluekube

# Download Kubernetes GPG key at build time
RUN K8S_MINOR=$(echo $kubernetes_version | cut -d. -f1,2) && \
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" -o /opt/gluekube/kubernetes-release.key

# Define default command
CMD ["bash"]
