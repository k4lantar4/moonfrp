# Ansible Development Workflow Guide

This guide explains how to use Ansible in the MoonFRP development workflow, including setting up development environments, testing strategies, and CI/CD integration.

## Table of Contents

- [Development Environment Setup](#development-environment-setup)
- [Using Ansible for Testing MoonFRP Features](#using-ansible-for-testing-moonfrp-features)
- [Local Development with Vagrant/Docker](#local-development-with-vagrantdocker)
- [CI/CD Integration Patterns](#cicd-integration-patterns)
- [Multi-Server Testing Scenarios](#multi-server-testing-scenarios)
- [Debugging and Troubleshooting](#debugging-and-troubleshooting)
- [Development Best Practices](#development-best-practices)

## Development Environment Setup

### Prerequisites

**Required Software**:
- Ansible 2.9+ or 4.0+
- Python 3.6+
- SSH client
- Git

**Installation**:

```bash
# Install Ansible
pip3 install ansible

# Or via package manager
sudo apt update
sudo apt install ansible

# Verify installation
ansible --version
```

### Project Setup

**Clone Repository**:
```bash
git clone https://github.com/k4lantar4/moonfrp.git
cd moonfrp
```

**Configure Ansible**:
```bash
cd ansible

# Copy example inventory if needed
cp hosts.example hosts

# Edit inventory with your test servers
nano hosts

# Test connectivity
ansible all -i hosts -m ping
```

**Setup SSH Keys**:
```bash
# Generate SSH key if needed
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_ansible

# Copy to test servers
ssh-copy-id -i ~/.ssh/id_rsa_ansible.pub user@server

# Test SSH access
ssh -i ~/.ssh/id_rsa_ansible user@server
```

### Development Directory Structure

```
moonfrp/
├── ansible/                 # Ansible automation
│   ├── playbooks/          # Playbooks for testing
│   ├── roles/              # Roles for development
│   └── test/               # Test-specific files
├── tests/                  # MoonFRP test suite
│   ├── test_*.sh          # Individual test scripts
│   └── metrics/           # Performance tests
└── docs/                   # Documentation
```

## Using Ansible for Testing MoonFRP Features

### Test Playbook Structure

Create test playbooks in `ansible/playbooks/test/`:

```yaml
---
# Test Playbook for MoonFRP Feature
# Usage: ansible-playbook -i hosts playbooks/test/test-feature.yml

- name: "Test MoonFRP Feature"
  hosts: test_servers
  become: yes
  gather_facts: yes

  vars:
    test_feature_enabled: true
    test_timeout: 300

  tasks:
    - name: "Install MoonFRP"
      include_role:
        name: moonfrp_install

    - name: "Setup test environment"
      block:
        - name: "Create test configuration"
          template:
            src: test-config.j2
            dest: /tmp/test-config.yml

        - name: "Run MoonFRP feature test"
          command: moonfrp test-feature --config /tmp/test-config.yml
          register: test_result
          failed_when: test_result.rc != 0

        - name: "Validate test output"
          assert:
            that:
              - "'success' in test_result.stdout"
              - "test_result.rc == 0"
            fail_msg: "Feature test failed"
            success_msg: "Feature test passed"

      rescue:
        - name: "Collect test logs"
          fetch:
            src: /var/log/moonfrp/test.log
            dest: "{{ playbook_dir }}/test-results/{{ inventory_hostname }}-test.log"
            flat: yes
            fail_on_missing: no

        - name: "Report test failure"
          debug:
            msg: "Test failed on {{ inventory_hostname }}"

  post_tasks:
    - name: "Cleanup test environment"
      file:
        path: /tmp/test-config.yml
        state: absent

    - name: "Display test summary"
      debug:
        msg: "Test completed for {{ inventory_hostname }}"
```

### Integration with MoonFRP Test Suite

**Running MoonFRP Tests via Ansible**:

```yaml
---
- name: "Run MoonFRP Test Suite"
  hosts: test_servers
  become: yes

  tasks:
    - name: "Clone MoonFRP repository"
      git:
        repo: https://github.com/k4lantar4/moonfrp.git
        dest: /tmp/moonfrp-test
        version: main

    - name: "Run specific test"
      shell: |
        cd /tmp/moonfrp-test
        chmod +x tests/test_config_validation.sh
        sudo ./tests/test_config_validation.sh
      register: test_output
      changed_when: false

    - name: "Display test results"
      debug:
        var: test_output.stdout_lines

    - name: "Collect test artifacts"
      fetch:
        src: /tmp/moonfrp-test/test-results/
        dest: "{{ playbook_dir }}/test-artifacts/{{ inventory_hostname }}/"
        flat: no
      when: test_output.rc == 0
```

### Feature Testing Workflow

1. **Develop Feature Locally**
   ```bash
   # Make changes to MoonFRP
   nano moonfrp-core.sh
   ```

2. **Create Test Playbook**
   ```bash
   # Create test playbook for feature
   nano ansible/playbooks/test/test-new-feature.yml
   ```

3. **Run Test on Single Server**
   ```bash
   # Test on one server first
   ansible-playbook -i hosts \
     playbooks/test/test-new-feature.yml \
     --limit test_server_01
   ```

4. **Run Full Test Suite**
   ```bash
   # Test on all servers
   ansible-playbook -i hosts \
     playbooks/test/test-new-feature.yml
   ```

5. **Validate Results**
   ```bash
   # Check test artifacts
   ls -la ansible/test-artifacts/
   ```

## Local Development with Vagrant/Docker

### Vagrant Setup

**Vagrantfile** (`ansible/Vagrantfile`):

```ruby
Vagrant.configure("2") do |config|
  # Iran Server (FRP Server)
  config.vm.define "ir_server01" do |ir|
    ir.vm.box = "ubuntu/jammy64"
    ir.vm.hostname = "ir-server01"
    ir.vm.network "private_network", ip: "192.168.56.10"
    ir.vm.provider "virtualbox" do |vb|
      vb.memory = "512"
      vb.cpus = 1
    end
  end

  # Kharej Server (FRP Client)
  config.vm.define "kh_server01" do |kh|
    kh.vm.box = "ubuntu/jammy64"
    kh.vm.hostname = "kh-server01"
    kh.vm.network "private_network", ip: "192.168.56.11"
    kh.vm.provider "virtualbox" do |vb|
      vb.memory = "512"
      vb.cpus = 1
    end
  end

  # Provision with Ansible
  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "playbooks/full-deployment.yml"
    ansible.inventory_path = "inventory/vagrant"
    ansible.limit = "all"
  end
end
```

**Vagrant Inventory** (`ansible/inventory/vagrant`):

```ini
[iran]
ir_server01 ansible_host=192.168.56.10

[kharej]
kh_server01 ansible_host=192.168.56.11

[panel_servers:children]
iran
kharej
```

**Usage**:

```bash
# Start Vagrant VMs
cd ansible
vagrant up

# Run Ansible playbook
ansible-playbook -i inventory/vagrant playbooks/full-deployment.yml

# SSH into VM
vagrant ssh ir_server01

# Destroy VMs
vagrant destroy
```

### Docker Setup

**Docker Compose** (`ansible/docker-compose.yml`):

```yaml
version: '3.8'

services:
  ir-server01:
    image: ubuntu:22.04
    container_name: ir-server01
    hostname: ir-server01
    networks:
      moonfrp-net:
        ipv4_address: 172.20.0.10
    volumes:
      - ./playbooks:/ansible/playbooks
    command: /bin/bash -c "apt-get update && apt-get install -y openssh-server && service ssh start && tail -f /dev/null"

  kh-server01:
    image: ubuntu:22.04
    container_name: kh-server01
    hostname: kh-server01
    networks:
      moonfrp-net:
        ipv4_address: 172.20.0.11
    volumes:
      - ./playbooks:/ansible/playbooks
    command: /bin/bash -c "apt-get update && apt-get install -y openssh-server && service ssh start && tail -f /dev/null"

networks:
  moonfrp-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

**Docker Inventory** (`ansible/inventory/docker`):

```ini
[iran]
ir_server01 ansible_host=172.20.0.10 ansible_user=root

[kharej]
kh_server01 ansible_host=172.20.0.11 ansible_user=root

[panel_servers:children]
iran
kharej
```

**Usage**:

```bash
# Start containers
cd ansible
docker-compose up -d

# Setup SSH keys in containers
docker exec -it ir-server01 bash -c "mkdir -p /root/.ssh && echo 'YOUR_PUBLIC_KEY' >> /root/.ssh/authorized_keys"

# Run Ansible
ansible-playbook -i inventory/docker playbooks/full-deployment.yml

# Stop containers
docker-compose down
```

## CI/CD Integration Patterns

### GitHub Actions

**Workflow File** (`.github/workflows/ansible-test.yml`):

```yaml
name: Ansible Test

on:
  push:
    branches: [ main, develop ]
    paths:
      - 'ansible/**'
      - 'moonfrp*.sh'
  pull_request:
    branches: [ main, develop ]
  workflow_dispatch:

jobs:
  syntax-check:
    name: Ansible Syntax Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Ansible
        run: |
          pip3 install ansible

      - name: Check playbook syntax
        run: |
          cd ansible
          ansible-playbook --syntax-check playbooks/*.yml

      - name: Check role syntax
        run: |
          cd ansible
          for role in roles/*/; do
            ansible-playbook --syntax-check -e "role_path=$role" test-role.yml || true
          done

  lint:
    name: Ansible Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Ansible Lint
        run: |
          pip3 install ansible-lint

      - name: Run Ansible Lint
        run: |
          cd ansible
          ansible-lint playbooks/*.yml

  test:
    name: Test Playbooks
    runs-on: ubuntu-latest
    needs: [syntax-check, lint]
    strategy:
      matrix:
        playbook:
          - deploy-moonfrp.yml
          - configure-servers.yml
          - configure-clients.yml
    steps:
      - uses: actions/checkout@v4

      - name: Install Ansible
        run: |
          pip3 install ansible

      - name: Test playbook (dry-run)
        run: |
          cd ansible
          ansible-playbook --check --diff \
            -i localhost, \
            playbooks/${{ matrix.playbook }} \
            --connection=local

  integration-test:
    name: Integration Test
    runs-on: ubuntu-latest
    needs: [syntax-check]
    steps:
      - uses: actions/checkout@v4

      - name: Install Ansible
        run: |
          pip3 install ansible

      - name: Setup test environment
        run: |
          # Setup test servers or use Docker
          docker-compose -f ansible/docker-compose.yml up -d

      - name: Run integration tests
        run: |
          cd ansible
          ansible-playbook -i inventory/docker \
            playbooks/test/integration-test.yml

      - name: Cleanup
        if: always()
        run: |
          docker-compose -f ansible/docker-compose.yml down
```

### GitLab CI

**GitLab CI Configuration** (`.gitlab-ci.yml`):

```yaml
stages:
  - validate
  - test
  - deploy

variables:
  ANSIBLE_HOST_KEY_CHECKING: "False"

ansible-syntax:
  stage: validate
  image: quay.io/ansible/molecule:latest
  script:
    - cd ansible
    - ansible-playbook --syntax-check playbooks/*.yml
  only:
    - merge_requests
    - main

ansible-lint:
  stage: validate
  image: quay.io/ansible/molecule:latest
  script:
    - cd ansible
    - ansible-lint playbooks/*.yml
  only:
    - merge_requests
    - main

ansible-test:
  stage: test
  image: quay.io/ansible/molecule:latest
  script:
    - cd ansible
    - ansible-playbook --check -i localhost, playbooks/full-deployment.yml --connection=local
  only:
    - merge_requests
    - main

ansible-deploy:
  stage: deploy
  image: quay.io/ansible/molecule:latest
  script:
    - cd ansible
    - ansible-playbook -i hosts playbooks/full-deployment.yml --ask-vault-pass
  only:
    - main
  when: manual
```

### Jenkins Pipeline

**Jenkinsfile**:

```groovy
pipeline {
    agent any

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Ansible Syntax Check') {
            steps {
                sh '''
                    cd ansible
                    ansible-playbook --syntax-check playbooks/*.yml
                '''
            }
        }

        stage('Ansible Lint') {
            steps {
                sh '''
                    pip3 install ansible-lint
                    cd ansible
                    ansible-lint playbooks/*.yml
                '''
            }
        }

        stage('Dry Run Test') {
            steps {
                sh '''
                    cd ansible
                    ansible-playbook --check -i localhost, \
                        playbooks/full-deployment.yml \
                        --connection=local
                '''
            }
        }

        stage('Integration Test') {
            steps {
                sh '''
                    cd ansible
                    docker-compose up -d
                    sleep 10
                    ansible-playbook -i inventory/docker \
                        playbooks/test/integration-test.yml
                '''
            }
            post {
                always {
                    sh 'cd ansible && docker-compose down'
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'ansible/test-results/**/*', allowEmptyArchive: true
        }
    }
}
```

## Multi-Server Testing Scenarios

### Testing Server-Client Pairing

**Test Playbook** (`ansible/playbooks/test/test-pairing.yml`):

```yaml
---
- name: "Test Server-Client Pairing"
  hosts: panel_servers
  become: yes

  tasks:
    - name: "Deploy MoonFRP"
      include_role:
        name: moonfrp_install

    - name: "Configure Iran servers"
      include_role:
        name: moonfrp_server
      when: inventory_hostname in groups['iran']

    - name: "Configure Kharej servers"
      include_role:
        name: moonfrp_client
      when: inventory_hostname in groups['kharej']

    - name: "Test connectivity from client to server"
      wait_for:
        host: "{{ hostvars[paired_server]['ansible_default_ipv4']['address'] }}"
        port: "{{ tunnel_port | default(7000) }}"
        timeout: 10
      when:
        - inventory_hostname in groups['kharej']
        - paired_server is defined
      register: connectivity_test

    - name: "Report pairing status"
      debug:
        msg: |
          Server: {{ inventory_hostname }}
          Paired with: {{ paired_server | default('N/A') }}
          Connectivity: {{ 'OK' if connectivity_test.failed == false else 'FAILED' }}
```

### Testing Multi-IP Configuration

**Test Playbook** (`ansible/playbooks/test/test-multi-ip.yml`):

```yaml
---
- name: "Test Multi-IP Configuration"
  hosts: kharej
  become: yes

  vars:
    test_server_ips:
      - "192.168.1.10"
      - "192.168.1.11"
      - "192.168.1.12"

  tasks:
    - name: "Configure multi-IP client"
      include_role:
        name: moonfrp_client
      vars:
        moonfrp_client_mode: "multi-ip"
        moonfrp_client_server_ips: "{{ test_server_ips }}"
        moonfrp_client_server_ports: [7000, 7000, 7000]
        moonfrp_client_local_ports: [8080, 8081, 8082]

    - name: "Verify multi-IP configuration files"
      find:
        paths: /etc/frp
        patterns: "frpc-*.toml"
      register: multi_ip_configs

    - name: "Validate configuration count"
      assert:
        that:
          - multi_ip_configs.files | length == test_server_ips | length
        fail_msg: "Expected {{ test_server_ips | length }} config files, found {{ multi_ip_configs.files | length }}"

    - name: "Test each IP connection"
      wait_for:
        host: "{{ item }}"
        port: 7000
        timeout: 5
      loop: "{{ test_server_ips }}"
      register: ip_tests

    - name: "Report test results"
      debug:
        msg: "IP {{ item.item }}: {{ 'OK' if item.failed == false else 'FAILED' }}"
      loop: "{{ ip_tests.results }}"
```

### Load Testing

**Load Test Playbook** (`ansible/playbooks/test/load-test.yml`):

```yaml
---
- name: "MoonFRP Load Test"
  hosts: test_servers
  become: yes

  vars:
    load_test_duration: 300  # seconds
    concurrent_connections: 100

  tasks:
    - name: "Install load testing tools"
      apt:
        name:
          - apache2-utils
          - netcat
        state: present

    - name: "Run load test"
      shell: |
        for i in $(seq 1 {{ concurrent_connections }}); do
          (timeout {{ load_test_duration }} \
            nc -zv {{ moonfrp_server_host }} {{ moonfrp_server_port }} \
            > /tmp/load-test-$i.log 2>&1) &
        done
        wait
      register: load_test

    - name: "Collect load test results"
      find:
        paths: /tmp
        patterns: "load-test-*.log"
      register: load_test_logs

    - name: "Analyze results"
      shell: |
        total=$(ls /tmp/load-test-*.log | wc -l)
        success=$(grep -l "succeeded" /tmp/load-test-*.log | wc -l)
        echo "Total: $total, Success: $success"
      register: load_analysis

    - name: "Display results"
      debug:
        msg: "{{ load_analysis.stdout }}"
```

## Debugging and Troubleshooting

### Debugging Techniques

**Verbose Output**:
```bash
# Different verbosity levels
ansible-playbook -v playbook.yml      # Verbose
ansible-playbook -vv playbook.yml     # More verbose
ansible-playbook -vvv playbook.yml    # Maximum verbosity
```

**Debug Specific Task**:
```yaml
- name: "Debug task"
  debug:
    msg: "Variable value: {{ my_variable }}"
    var: my_variable
    var: hostvars[inventory_hostname]
```

**Check Mode**:
```bash
# See what would change
ansible-playbook --check playbook.yml

# With diff
ansible-playbook --check --diff playbook.yml
```

**Step-by-Step Execution**:
```bash
# Run one task at a time
ansible-playbook --step playbook.yml
```

### Common Issues and Solutions

**Issue: Connection Refused**
```bash
# Check SSH connectivity
ansible all -i hosts -m ping

# Test SSH manually
ssh user@server

# Check SSH configuration
ansible all -i hosts -m setup -a "filter=ansible_ssh_*"
```

**Issue: Permission Denied**
```bash
# Use become
ansible-playbook --become playbook.yml

# Check sudo access
ansible all -i hosts -m command -a "sudo whoami" --become
```

**Issue: Variable Not Defined**
```bash
# List all variables
ansible-playbook --list-hosts playbook.yml
ansible-inventory -i hosts --list

# Debug variable resolution
ansible-playbook -vvv playbook.yml | grep "variable_name"
```

**Issue: Task Fails Unexpectedly**
```yaml
# Add error handling
- name: "Risky task"
  command: risky_command
  register: result
  failed_when: false
  changed_when: false

- name: "Check result"
  debug:
    var: result

- name: "Fail if needed"
  fail:
    msg: "Task failed: {{ result.stderr }}"
  when: result.rc != 0
```

### Logging and Artifact Collection

**Collect Logs**:
```yaml
- name: "Collect MoonFRP logs"
  fetch:
    src: /var/log/moonfrp/moonfrp.log
    dest: "{{ playbook_dir }}/logs/{{ inventory_hostname }}-moonfrp.log"
    flat: yes
    fail_on_missing: no

- name: "Collect system logs"
  fetch:
    src: /var/log/syslog
    dest: "{{ playbook_dir }}/logs/{{ inventory_hostname }}-syslog"
    flat: yes
    fail_on_missing: no
```

## Development Best Practices

### 1. Version Control

- Commit playbooks and roles frequently
- Use descriptive commit messages
- Tag releases
- Keep secrets in Ansible Vault

### 2. Testing Strategy

- Test on single server first
- Use check mode before real execution
- Test idempotency (run twice)
- Validate syntax before committing

### 3. Documentation

- Document all variables
- Include usage examples
- Keep README updated
- Comment complex logic

### 4. Security

- Use Ansible Vault for secrets
- Limit SSH access
- Use least privilege (become only when needed)
- Review playbooks for security issues

### 5. Performance

- Use `async` for long-running tasks
- Limit hosts when testing
- Use `run_once` for tasks that don't need per-host execution
- Optimize fact gathering

### 6. Code Organization

- Keep roles focused and reusable
- Use consistent naming
- Group related tasks
- Extract common patterns

### 7. Error Handling

- Use appropriate error handling
- Provide clear error messages
- Collect logs on failure
- Implement retry logic where appropriate

## Summary

This workflow guide provides:

1. **Environment Setup**: Complete development environment configuration
2. **Testing Integration**: Using Ansible with MoonFRP test suite
3. **Local Development**: Vagrant and Docker setups
4. **CI/CD Integration**: GitHub Actions, GitLab CI, Jenkins examples
5. **Multi-Server Testing**: Complex testing scenarios
6. **Debugging**: Techniques and troubleshooting
7. **Best Practices**: Development guidelines

Following this workflow ensures:
- Consistent development environments
- Reliable testing procedures
- Automated CI/CD pipelines
- Effective debugging and troubleshooting
- Maintainable and secure automation

