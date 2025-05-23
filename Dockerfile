FROM ubuntu:24.10@sha256:aadf9a3f5eda81295050d13dabe851b26a67597e424a908f25a63f589dfed48f
ENV ANSIBLE_VERSION 2.16.14
RUN apt-get update; \
    apt-get install -y gcc python3; \
    apt-get install -y python3-pip; \
    apt-get clean all
RUN pip3 install --upgrade pip; \
    pip3 install "ansible==${ANSIBLE_VERSION}"; \
    pip3 install ansible
