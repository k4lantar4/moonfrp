# MoonFRP Docker Test Environment

This Docker environment simulates production servers with existing FRP installations, allowing safe testing of MoonFRP deployment via Ansible.

## Features

- Simulates existing FRP installations (version 0.63.0)
- Pre-configured with `/opt/frp` and `/etc/frp` (conflict scenarios)
- Multiple test servers for different configurations
- Isolated from production systems

## Quick Start

### 1. Build and Start Containers

```bash
cd docker/test-environment
docker-compose up -d
```

### 2. Create Ansible Inventory

Create `ansible/hosts-test`:

```ini
[test_servers]
test-server-1 ansible_host=test-server-1 ansible_connection=docker
test-server-2 ansible_host=test-server-2 ansible_connection=docker

[test_servers:vars]
ansible_user=ansible
ansible_python_interpreter=/usr/bin/python3
```

### 3. Run Dry-Run Deployment

```bash
cd ansible
ansible-playbook -i hosts-test playbooks/deploy-moonfrp-dry-run.yml
```

### 4. Run Actual Deployment (Test)

```bash
ansible-playbook -i hosts-test playbooks/deploy-moonfrp.yml \
  -e "moonfrp_fail_on_conflict=false"
```

### 5. Verify Installation

```bash
docker exec -it moonfrp-test-server-1 moonfrp --version
docker exec -it moonfrp-test-server-1 ls -la /opt/moonfrp/frp
docker exec -it moonfrp-test-server-1 ls -la /etc/moonfrp/frp
```

## Test Scenarios

### Scenario 1: Existing FRP Installation (Conflict Detection)

The containers come pre-configured with:
- `/opt/frp/frps` and `/opt/frp/frpc` binaries
- `/etc/frp/frps.toml` and `/etc/frp/frpc.toml` configs
- Systemd service `frps.service`

MoonFRP should:
- Detect existing installation
- Use isolated paths (`/opt/moonfrp/frp`, `/etc/moonfrp/frp`)
- Not modify existing files
- Report conflicts (warn or fail based on `moonfrp_fail_on_conflict`)

### Scenario 2: Port Conflicts

Test servers use ports 7000 and 7500. MoonFRP should:
- Detect port usage
- Report conflicts
- Allow configuration of alternative ports

### Scenario 3: Version Compatibility

Test with different FRP versions:
- Server 1: FRP 0.63.0 (existing)
- Server 2: FRP 0.65.0 (new)

## Environment Variables

You can override paths via environment variables in `docker-compose.yml`:

```yaml
environment:
  - FRP_DIR=/opt/moonfrp/frp
  - MOONFRP_CONFIG_DIR=/etc/moonfrp/frp
  - MOONFRP_LOG_DIR=/var/log/moonfrp
  - FRP_VERSION=0.65.0
```

## Cleanup

```bash
docker-compose down -v
```

This removes containers and volumes.

## Integration with CI/CD

Example GitHub Actions workflow:

```yaml
- name: Test MoonFRP Deployment
  run: |
    cd docker/test-environment
    docker-compose up -d
    sleep 10
    cd ../../ansible
    ansible-playbook -i hosts-test playbooks/deploy-moonfrp-dry-run.yml
```

