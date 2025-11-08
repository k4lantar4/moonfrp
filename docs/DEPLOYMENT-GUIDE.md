# MoonFRP Deployment Guide

This guide covers deploying MoonFRP to production servers with existing FRP installations using Ansible.

## Table of Contents

1. [Overview](#overview)
2. [Pre-Deployment Checks](#pre-deployment-checks)
3. [Configuration](#configuration)
4. [Deployment](#deployment)
5. [Testing](#testing)
6. [Troubleshooting](#troubleshooting)

## Overview

MoonFRP is designed to coexist with existing FRP installations by using isolated paths and service names. This ensures no conflicts with production systems.

### Key Features

- **Path Isolation**: Uses `/opt/moonfrp/frp` instead of `/opt/frp`
- **Config Isolation**: Uses `/etc/moonfrp/frp` instead of `/etc/frp`
- **Service Isolation**: Uses `moonfrp-*` service names
- **Conflict Detection**: Automatically detects existing installations
- **Dry-Run Mode**: Test deployments without making changes

## Pre-Deployment Checks

### 1. Check Existing FRP Installation

```bash
# Check for existing FRP binaries
ls -la /opt/frp/

# Check for existing configs
ls -la /etc/frp/

# Check for existing services
systemctl list-units --type=service | grep -E '(frps|frpc)'
```

### 2. Check Port Usage

```bash
# Check if default ports are in use
netstat -tuln | grep -E ':(7000|7500)'
```

### 3. Run Dry-Run Deployment

```bash
cd ansible
ansible-playbook -i hosts playbooks/deploy-moonfrp-dry-run.yml
```

This will:
- Detect existing FRP installations
- Check for port conflicts
- Check for service conflicts
- Report all findings without making changes

## Configuration

### Environment Variables

MoonFRP supports the following environment variables for path customization:

| Variable | Default | Description |
|----------|---------|-------------|
| `FRP_DIR` | `/opt/moonfrp/frp` | FRP binary installation directory |
| `MOONFRP_CONFIG_DIR` | `/etc/moonfrp/frp` | FRP configuration directory |
| `MOONFRP_LOG_DIR` | `/var/log/moonfrp` | FRP log directory |
| `FRP_VERSION` | `0.65.0` | FRP version to install |
| `FRP_ARCH` | `auto` | FRP architecture (auto-detect) |

### Ansible Variables

Configure in `ansible/group_vars/all/moonfrp.yml` or per-host:

```yaml
# Path Isolation
moonfrp_frp_dir: "/opt/moonfrp/frp"
moonfrp_config_dir_frp: "/etc/moonfrp/frp"
moonfrp_log_dir: "/var/log/moonfrp"

# FRP Version (can override per-host)
frp_version: "0.65.0"  # Or "0.63.0" for existing servers

# Pre-deployment Checks
moonfrp_check_existing_files: true
moonfrp_check_ports: true
moonfrp_check_services: true
moonfrp_fail_on_conflict: false  # true = fail, false = warn
```

### Per-Host Configuration

For servers with existing FRP 0.63.0 installations:

```yaml
# In host_vars/server-name.yml
frp_version: "0.63.0"
moonfrp_frp_dir: "/opt/moonfrp/frp"
moonfrp_config_dir_frp: "/etc/moonfrp/frp"
```

## Deployment

### Step 1: Dry-Run (Recommended)

Always run dry-run first:

```bash
ansible-playbook -i hosts playbooks/deploy-moonfrp-dry-run.yml
```

Review the output for:
- Existing file conflicts
- Port conflicts
- Service conflicts

### Step 2: Deploy

If dry-run passes, deploy:

```bash
ansible-playbook -i hosts playbooks/deploy-moonfrp.yml
```

### Step 3: Verify

```bash
# Check MoonFRP installation
ansible all -i hosts -m command -a "moonfrp --version"

# Check FRP binaries location
ansible all -i hosts -m command -a "ls -la /opt/moonfrp/frp/"

# Check configs location
ansible all -i hosts -m command -a "ls -la /etc/moonfrp/frp/"

# Check services
ansible all -i hosts -m systemd -a "name=moonfrp-server state=started"
```

## Testing

### Docker Test Environment

Use the Docker test environment to simulate production scenarios:

```bash
cd docker/test-environment
docker-compose up -d

# Create test inventory
cp ../../ansible/hosts-test.example ../../ansible/hosts-test

# Run dry-run
cd ../../ansible
ansible-playbook -i hosts-test playbooks/deploy-moonfrp-dry-run.yml

# Run deployment
ansible-playbook -i hosts-test playbooks/deploy-moonfrp.yml \
  -e "moonfrp_fail_on_conflict=false"
```

### Test Scenarios

1. **Existing FRP Installation**: Containers come with `/opt/frp` and `/etc/frp`
2. **Port Conflicts**: Test servers use ports 7000 and 7500
3. **Version Compatibility**: Test with different FRP versions

## Troubleshooting

### Issue: Existing FRP Installation Detected

**Solution**: MoonFRP will use isolated paths automatically. If you want to fail on conflicts:

```yaml
moonfrp_fail_on_conflict: true
```

### Issue: Port Conflicts

**Solution**: Configure different ports:

```yaml
moonfrp_server_bind_port: 7001
moonfrp_server_dashboard_port: 7501
```

### Issue: Service Conflicts

**Solution**: MoonFRP uses `moonfrp-*` service names, so conflicts are unlikely. If needed, check:

```bash
systemctl list-units --type=service | grep moonfrp
```

### Issue: Path Not Writable

**Solution**: Ensure directories exist and are writable:

```bash
sudo mkdir -p /opt/moonfrp/frp /etc/moonfrp/frp /var/log/moonfrp
sudo chown -R $USER:$USER /opt/moonfrp /etc/moonfrp /var/log/moonfrp
```

## Best Practices

1. **Always run dry-run first** before production deployment
2. **Test in Docker environment** to simulate production scenarios
3. **Use isolated paths** to avoid conflicts with existing installations
4. **Monitor logs** after deployment: `/var/log/moonfrp/`
5. **Keep backups** of existing configurations before deployment
6. **Use version control** for Ansible playbooks and configurations

## Example: Deploying to Server with Existing FRP 0.63.0

```bash
# 1. Create host-specific vars
cat > ansible/host_vars/production-server.yml << EOF
frp_version: "0.63.0"
moonfrp_frp_dir: "/opt/moonfrp/frp"
moonfrp_config_dir_frp: "/etc/moonfrp/frp"
moonfrp_fail_on_conflict: false
EOF

# 2. Run dry-run
ansible-playbook -i hosts playbooks/deploy-moonfrp-dry-run.yml \
  --limit production-server

# 3. Deploy
ansible-playbook -i hosts playbooks/deploy-moonfrp.yml \
  --limit production-server
```

## Additional Resources

- [Docker Test Environment README](../docker/test-environment/README.md)
- [Ansible Role Documentation](../ansible/README-MOONFRP.md)
- [MoonFRP Main Documentation](../README.md)

