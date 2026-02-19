ARG OPENSHIFT_VERSION=4.20

FROM registry.access.redhat.com/ubi9/ubi:latest

# Install required system packages
RUN dnf install -y \
    python3 \
    python3-pip \
    git \
    wget \
    unzip \
    tar \
    jq \
    && dnf clean all

# Install Ansible and required Python packages
RUN pip3 install --no-cache-dir \
    ansible>=2.14 \
    boto3 \
    botocore \
    jinja2

# Install Ansible collections
RUN ansible-galaxy collection install \
    amazon.aws \
    community.general

# Install OpenShift CLI (oc)
ARG OPENSHIFT_VERSION
RUN wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OPENSHIFT_VERSION}/openshift-client-linux.tar.gz && \
    tar -xzf openshift-client-linux.tar.gz -C /usr/local/bin/ && \
    rm openshift-client-linux.tar.gz && \
    chmod +x /usr/local/bin/oc /usr/local/bin/kubectl

# Install OpenShift Installer
RUN wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OPENSHIFT_VERSION}/openshift-install-linux.tar.gz && \
    tar -xzf openshift-install-linux.tar.gz -C /usr/local/bin/ && \
    rm openshift-install-linux.tar.gz && \
    chmod +x /usr/local/bin/openshift-install

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Create workspace directory
WORKDIR /workspace

# Set entrypoint and default command
ENTRYPOINT ["ansible-playbook"]
CMD ["--version"]
