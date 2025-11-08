# Docker test environment for MoonFRP deployment simulation
# Simulates a production server with existing FRP installation

FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    systemd \
    bash \
    net-tools \
    iproute2 \
    python3 \
    python3-pip \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Ansible
RUN pip3 install ansible

# Create existing FRP installation (simulating production environment)
RUN mkdir -p /opt/frp /etc/frp /var/log/frp

# Create mock FRP binaries
RUN touch /opt/frp/frps /opt/frp/frpc && \
    chmod +x /opt/frp/frps /opt/frp/frpc

# Create mock FRP config files
RUN echo "[common]" > /etc/frp/frps.toml && \
    echo "bind_port = 7000" >> /etc/frp/frps.toml && \
    echo "[common]" > /etc/frp/frpc.toml && \
    echo "server_addr = 1.1.1.1" >> /etc/frp/frpc.toml

# Create systemd service files (mock)
RUN mkdir -p /etc/systemd/system && \
    echo "[Unit]" > /etc/systemd/system/frps.service && \
    echo "Description=FRP Server" >> /etc/systemd/system/frps.service && \
    echo "[Service]" >> /etc/systemd/system/frps.service && \
    echo "ExecStart=/opt/frp/frps -c /etc/frp/frps.toml" >> /etc/systemd/system/frps.service

# Create test user for Ansible
RUN useradd -m -s /bin/bash ansible && \
    echo "ansible ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set working directory
WORKDIR /workspace

# Copy Ansible playbooks (will be mounted as volume)
VOLUME ["/workspace"]

# Keep container running
CMD ["/bin/bash", "-c", "tail -f /dev/null"]

