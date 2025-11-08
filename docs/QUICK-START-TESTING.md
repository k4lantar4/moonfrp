# Quick Start: Testing MoonFRP Deployment

This is a quick guide to test MoonFRP deployment in an isolated Docker environment before deploying to production.

## Prerequisites

- Docker and Docker Compose installed
- Ansible installed (for running playbooks)

## Step 1: Start Test Environment

```bash
cd docker/test-environment
docker-compose up -d
```

Wait for containers to start (about 10-15 seconds).

## Step 2: Create Test Inventory

```bash
cd ../../ansible
cp hosts-test.example hosts-test
```

## Step 3: Run Dry-Run

Check for conflicts without making changes:

```bash
ansible-playbook -i hosts-test playbooks/deploy-moonfrp-dry-run.yml
```

Expected output:
- Detection of existing FRP files in `/opt/frp` and `/etc/frp`
- Port conflict checks
- Service conflict checks
- Summary of what would be deployed

## Step 4: Run Actual Deployment (Test)

```bash
ansible-playbook -i hosts-test playbooks/deploy-moonfrp.yml \
  -e "moonfrp_fail_on_conflict=false"
```

## Step 5: Verify Installation

```bash
# Check MoonFRP is installed
docker exec -it moonfrp-test-server-1 moonfrp --version

# Check isolated paths
docker exec -it moonfrp-test-server-1 ls -la /opt/moonfrp/frp/
docker exec -it moonfrp-test-server-1 ls -la /etc/moonfrp/frp/

# Verify existing FRP files are untouched
docker exec -it moonfrp-test-server-1 ls -la /opt/frp/
docker exec -it moonfrp-test-server-1 ls -la /etc/frp/
```

## Step 6: Cleanup

```bash
cd docker/test-environment
docker-compose down -v
```

## What to Look For

✅ **Success Indicators:**
- MoonFRP installed successfully
- Files in `/opt/moonfrp/frp` (isolated path)
- Configs in `/etc/moonfrp/frp` (isolated path)
- Existing files in `/opt/frp` and `/etc/frp` unchanged
- No port conflicts
- Services start correctly

❌ **Failure Indicators:**
- Errors during installation
- Conflicts with existing files
- Port conflicts not detected
- Services fail to start

## Next Steps

After successful testing:

1. Review the deployment guide: [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)
2. Configure production inventory
3. Run dry-run on production servers
4. Deploy to production

## Troubleshooting

### Containers won't start
```bash
docker-compose logs
```

### Ansible connection issues
```bash
# Test connection
ansible test_servers -i hosts-test -m ping
```

### Port conflicts in test
The test environment uses ports 7001, 7501, 7002, 7502. If these are in use, modify `docker-compose.yml`.

## See Also

- [Deployment Guide](DEPLOYMENT-GUIDE.md)
- [Environment Variables](ENVIRONMENT-VARIABLES.md)
- [Docker Test Environment README](../docker/test-environment/README.md)

