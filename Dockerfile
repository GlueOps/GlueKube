FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV kuberenetes_version="1.32.6"
ENV kubernetes_package_version="1.32.6-1.1"
ENV calico_tiger_operator_version="v1.36.7"
ENV calico_chart_version="v3.29.3"
ENV ANSIBLE_ROLES_PATH=/opt/gluekube/ansible/roles
ENV ANSIBLE_HOST_KEY_CHECKING=False

RUN apt-get update && apt-get upgrade -y && apt-get install -y build-essential

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ansible && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN pip install jmespath

WORKDIR /opt/gluekube

COPY . /opt/gluekube

CMD ["bash"]
