# MoonFRP Environment Variables Reference

This document describes all environment variables supported by MoonFRP for customization and path isolation.

## Core Configuration Variables

### `FRP_DIR`
- **Default**: `/opt/frp`
- **Recommended for production**: `/opt/moonfrp/frp`
- **Description**: Directory where FRP binaries (`frps`, `frpc`) are installed
- **Usage**: Set to avoid conflicts with existing FRP installations

```bash
export FRP_DIR="/opt/moonfrp/frp"
```

### `MOONFRP_CONFIG_DIR`
- **Default**: `/etc/frp`
- **Recommended for production**: `/etc/moonfrp/frp`
- **Description**: Directory where FRP configuration files are stored
- **Usage**: Set to avoid conflicts with existing FRP configs

```bash
export MOONFRP_CONFIG_DIR="/etc/moonfrp/frp"
```

### `MOONFRP_LOG_DIR`
- **Default**: `/var/log/frp`
- **Recommended for production**: `/var/log/moonfrp`
- **Description**: Directory where FRP log files are stored
- **Usage**: Centralized logging location

```bash
export MOONFRP_LOG_DIR="/var/log/moonfrp"
```

### `FRP_VERSION`
- **Default**: `0.65.0`
- **Description**: FRP version to install
- **Usage**: Specify version for compatibility with existing installations

```bash
export FRP_VERSION="0.63.0"  # For servers with existing FRP 0.63.0
```

### `FRP_ARCH`
- **Default**: `auto` (auto-detect)
- **Options**: `linux_amd64`, `linux_arm64`, `linux_armv7`
- **Description**: FRP architecture to install
- **Usage**: Override auto-detection if needed

```bash
export FRP_ARCH="linux_amd64"
```

## Server Configuration Variables

### `MOONFRP_SERVER_BIND_ADDR`
- **Default**: `0.0.0.0`
- **Description**: Server bind address

### `MOONFRP_SERVER_BIND_PORT`
- **Default**: `7000`
- **Description**: Server bind port
- **Usage**: Change if port 7000 is already in use

```bash
export MOONFRP_SERVER_BIND_PORT="7001"
```

### `MOONFRP_SERVER_AUTH_TOKEN`
- **Default**: Auto-generated
- **Description**: Server authentication token

### `MOONFRP_SERVER_DASHBOARD_PORT`
- **Default**: `7500`
- **Description**: Dashboard web interface port
- **Usage**: Change if port 7500 is already in use

```bash
export MOONFRP_SERVER_DASHBOARD_PORT="7501"
```

### `MOONFRP_SERVER_DASHBOARD_USER`
- **Default**: `admin`
- **Description**: Dashboard username

### `MOONFRP_SERVER_DASHBOARD_PASSWORD`
- **Default**: Auto-generated
- **Description**: Dashboard password

## Client Configuration Variables

### `MOONFRP_CLIENT_SERVER_ADDR`
- **Description**: Client server address (required)

### `MOONFRP_CLIENT_SERVER_PORT`
- **Default**: `7000`
- **Description**: Client server port

### `MOONFRP_CLIENT_AUTH_TOKEN`
- **Description**: Client authentication token (required)

### `MOONFRP_CLIENT_USER`
- **Default**: Auto-generated
- **Description**: Client username

## Using Environment Variables with Ansible

### Method 1: Set in Ansible Playbook

```yaml
- name: "Install MoonFRP"
  shell: |
    export FRP_DIR="/opt/moonfrp/frp"
    export MOONFRP_CONFIG_DIR="/etc/moonfrp/frp"
    export FRP_VERSION="0.65.0"
    moonfrp setup server
  environment:
    FRP_DIR: "/opt/moonfrp/frp"
    MOONFRP_CONFIG_DIR: "/etc/moonfrp/frp"
    FRP_VERSION: "0.65.0"
```

### Method 2: Set in Ansible Variables

```yaml
# In group_vars/all/moonfrp.yml
moonfrp_frp_dir: "/opt/moonfrp/frp"
moonfrp_config_dir_frp: "/etc/moonfrp/frp"
frp_version: "0.65.0"
```

### Method 3: Export Before Running

```bash
export FRP_DIR="/opt/moonfrp/frp"
export MOONFRP_CONFIG_DIR="/etc/moonfrp/frp"
export FRP_VERSION="0.65.0"
ansible-playbook playbooks/deploy-moonfrp.yml
```

## Production Deployment Example

For servers with existing FRP installations:

```bash
# Set isolated paths
export FRP_DIR="/opt/moonfrp/frp"
export MOONFRP_CONFIG_DIR="/etc/moonfrp/frp"
export MOONFRP_LOG_DIR="/var/log/moonfrp"

# Use existing FRP version for compatibility
export FRP_VERSION="0.63.0"

# Use alternative ports
export MOONFRP_SERVER_BIND_PORT="7001"
export MOONFRP_SERVER_DASHBOARD_PORT="7501"

# Deploy
ansible-playbook -i hosts playbooks/deploy-moonfrp.yml
```

## Verification

After setting environment variables, verify they're being used:

```bash
# Check FRP binary location
ls -la $FRP_DIR/

# Check config location
ls -la $MOONFRP_CONFIG_DIR/

# Check log location
ls -la $MOONFRP_LOG_DIR/
```

## Legacy Variables

For backward compatibility, these legacy variables are also supported:

- `MOONFRP_INSTALL_DIR` → Maps to `FRP_DIR`
- `MOONFRP_FRP_ARCH` → Maps to `FRP_ARCH`

## See Also

- [Deployment Guide](DEPLOYMENT-GUIDE.md)
- [Docker Test Environment](../docker/test-environment/README.md)

