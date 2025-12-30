FROM python:3.12-slim

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV kubernetes_version="v1.32.6"
ENV kubernetes_package_version="1.32.6-1.1"
ENV calico_tiger_operator_version="v1.36.7"
ENV calico_chart_version="v3.29.3"
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
    apt-get install jq -y

# Set working directory
WORKDIR /opt/gluekube

# Copy application files
COPY . /opt/gluekube

# Define default command
CMD ["bash"]