<p align="center">
  <img src="assets/logo.png" alt="MoonFRP Logo" width="160" height="160" />
</p>

# MoonFRP 🌙 v2.0.0

**Advanced FRP Management Tool** - A professional, modular bash script for managing FRP (Fast Reverse Proxy) configurations and services with ease.

<p align="center">
  <a href="https://github.com/k4lantar4/moonfrp/actions">
    <img alt="CI" src="https://img.shields.io/badge/CI-passing-4caf50?style=for-the-badge" />
  </a>
  <img alt="License" src="https://img.shields.io/badge/License-MIT-2f80ed?style=for-the-badge" />
  <img alt="Shell" src="https://img.shields.io/badge/Shell-bash-333?style=for-the-badge" />
</p>

## ✨ Key Features

- **🚀 One-Command Installation**: Install via single curl command with environment variable support
- **🔧 Modular Architecture**: Clean, maintainable codebase split into logical modules
- **📊 Professional Service Management**: Complete systemd integration with health monitoring
- **🔄 Multi-IP Support**: Advanced support for multiple server IPs with automatic configuration
- **🛡️ Security First**: Token-based authentication, TLS encryption, and secure defaults
- **📱 Intuitive UI**: Simple menu system with command-line interface
- **🔍 Comprehensive Logging**: Detailed logging with configurable levels
- **⚡ Performance Optimized**: Connection pooling, multiplexing, and bandwidth controls
- **🎯 Environment Variables**: All settings configurable via environment variables
- **🔧 Easy Configuration**: Interactive wizards and template system

## 🚀 Quick Installation

### One-Command Installation

```bash
# Basic installation
curl -fsSL https://raw.githubusercontent.com/k4lantar4/moonfrp/main/install.sh | bash

# With environment variables
curl -fsSL https://raw.githubusercontent.com/k4lantar4/moonfrp/main/install.sh | \
  MOONFRP_SERVER_BIND_PORT="7000" \
  MOONFRP_SERVER_AUTH_TOKEN="your-token" \
  bash
```

### Manual Installation

```bash
# Download and install
wget https://raw.githubusercontent.com/k4lantar4/moonfrp/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

## 🎯 Quick Start

### Interactive Mode

```bash
# Start MoonFRP
moonfrp

# Follow the interactive menu
```

### Command Line Mode

```bash
# Quick server setup
moonfrp setup server

# Quick client setup
moonfrp setup client

# Multi-IP setup
moonfrp setup multi-ip

# Service management
moonfrp service start all
moonfrp service status
moonfrp health check
```

## 🔧 Configuration

### Environment Variables

All settings can be configured via environment variables:

```bash
# Core Configuration
export MOONFRP_FRP_VERSION="0.65.0"
export MOONFRP_FRP_ARCH="linux_amd64"
export MOONFRP_INSTALL_DIR="/opt/frp"
export MOONFRP_CONFIG_DIR="/etc/frp"
export MOONFRP_LOG_DIR="/var/log/frp"

# Server Configuration
export MOONFRP_SERVER_BIND_ADDR="0.0.0.0"
export MOONFRP_SERVER_BIND_PORT="7000"
export MOONFRP_SERVER_AUTH_TOKEN="your-secure-token"
export MOONFRP_SERVER_DASHBOARD_PORT="7500"
export MOONFRP_SERVER_DASHBOARD_USER="admin"
export MOONFRP_SERVER_DASHBOARD_PASSWORD="your-password"

# Client Configuration
export MOONFRP_CLIENT_SERVER_ADDR="1.1.1.1"
export MOONFRP_CLIENT_SERVER_PORT="7000"
export MOONFRP_CLIENT_AUTH_TOKEN="your-secure-token"
export MOONFRP_CLIENT_USER="moonfrp"

# Multi-IP Configuration
export MOONFRP_SERVER_IPS="1.1.1.1,2.2.2.2,3.3.3.3"
export MOONFRP_SERVER_PORTS="7000,7000,7000"
export MOONFRP_CLIENT_PORTS="8080,8081,8082"

# Security Settings
export MOONFRP_TLS_ENABLE="true"
export MOONFRP_TLS_FORCE="false"
export MOONFRP_AUTH_METHOD="token"

# Performance Settings
export MOONFRP_MAX_POOL_COUNT="5"
export MOONFRP_POOL_COUNT="5"
export MOONFRP_TCP_MUX="true"
export MOONFRP_HEARTBEAT_INTERVAL="30"
export MOONFRP_HEARTBEAT_TIMEOUT="90"

# Logging Settings
export MOONFRP_LOG_LEVEL="info"
export MOONFRP_LOG_MAX_DAYS="7"
export MOONFRP_LOG_DISABLE_COLOR="false"
```

### Configuration File

Configuration is stored in `/etc/moonfrp/config` and can be edited directly:

```bash
# Edit configuration
sudo nano /etc/moonfrp/config

# Reload configuration
moonfrp config reload
```

## 📋 Usage Examples

### Server Setup (Iran Server)

```bash
# Basic server setup
moonfrp setup server

# With custom settings
MOONFRP_SERVER_BIND_PORT="7000" \
MOONFRP_SERVER_AUTH_TOKEN="my-secure-token" \
MOONFRP_SERVER_DASHBOARD_PASSWORD="admin123" \
moonfrp setup server
```

### Client Setup (Foreign Client)

```bash
# Basic client setup
moonfrp setup client

# With custom settings
MOONFRP_CLIENT_SERVER_ADDR="1.1.1.1" \
MOONFRP_CLIENT_AUTH_TOKEN="my-secure-token" \
MOONFRP_CLIENT_USER="my-client" \
moonfrp setup client
```

### Multi-IP Setup

```bash
# Multi-IP client setup
MOONFRP_SERVER_IPS="1.1.1.1,2.2.2.2,3.3.3.3" \
MOONFRP_SERVER_PORTS="7000,7000,7000" \
MOONFRP_CLIENT_PORTS="8080,8081,8082" \
MOONFRP_CLIENT_AUTH_TOKEN="my-secure-token" \
moonfrp setup multi-ip
```

### Service Management

```bash
# Start all services
moonfrp service start all

# Start specific service
moonfrp service start moonfrp-server

# Stop all services
moonfrp service stop all

# Restart all services
moonfrp service restart all

# Check service status
moonfrp service status

# View service logs
moonfrp service logs moonfrp-server

# Follow logs in real-time
moonfrp service logs moonfrp-server --follow
```

### Health Monitoring

```bash
# Check system health
moonfrp health check

# View system status
moonfrp status

# View logs
moonfrp logs
```

## 🏗️ Architecture

### Modular Design

MoonFRP v2.0.0 features a clean modular architecture:

```
moonfrp.sh          # Main entry point
├── moonfrp-core.sh     # Core utilities and functions
├── moonfrp-config.sh   # Configuration management
├── moonfrp-services.sh # Service management
└── moonfrp-ui.sh       # User interface and menus
```

### File Structure

```
/opt/frp/                    # FRP binaries
├── frps                     # FRP server binary
├── frpc                     # FRP client binary
├── moonfrp-core.sh          # Core functions
├── moonfrp-config.sh        # Configuration functions
├── moonfrp-services.sh      # Service functions
├── moonfrp-ui.sh            # UI functions
└── moonfrp.sh           # Main script

/etc/frp/                    # Configuration files
├── frps.toml               # Server configuration
├── frpc.toml               # Client configuration
├── frpc_1.toml             # Multi-IP client config 1
├── frpc_2.toml             # Multi-IP client config 2
└── backups/                # Configuration backups

/var/log/frp/               # Log files
├── frps.log                # Server logs
├── frpc.log                # Client logs
├── frpc_1.log              # Multi-IP client logs
└── moonfrp.log             # MoonFRP script logs

/etc/moonfrp/               # MoonFRP configuration
└── config                  # Environment variables

/etc/systemd/system/        # Systemd service files
├── moonfrp-server.service
├── moonfrp-client.service
├── moonfrp-client-1.service
└── moonfrp-client-2.service
```

## 🔧 Advanced Features

### 1. Multi-IP Load Balancing

Configure multiple Iran server IPs for load balancing and redundancy:

```bash
# Environment variables
export MOONFRP_SERVER_IPS="1.1.1.1,2.2.2.2,3.3.3.3,4.4.4.4"
export MOONFRP_SERVER_PORTS="7000,7000,7000,7000"
export MOONFRP_CLIENT_PORTS="8080,8081,8082,8083"

# Setup
moonfrp setup multi-ip
```

### 2. Service Health Monitoring

Built-in health checking and automatic restart:

```bash
# Health check
moonfrp health check

# Monitor services
moonfrp service status
```

### 3. Security Features

- **Token Authentication**: Secure token-based authentication
- **TLS Encryption**: End-to-end TLS encryption
- **Port Restrictions**: Configurable allowed port ranges
- **User Isolation**: Separate user namespaces for clients
- **Secure Defaults**: Security-first configuration

### 4. Performance Optimization

- **Connection Pooling**: Pre-established connection pools
- **Compression**: Optional traffic compression
- **Bandwidth Limiting**: Per-proxy bandwidth controls
- **Multiplexing**: TCP connection multiplexing
- **Resource Limits**: Systemd resource limits

## 🧪 Testing

### Fresh Server Test Suite

```bash
# Run comprehensive test suite
chmod +x test-fresh-install.sh
sudo ./test-fresh-install.sh
```

### Manual Testing

```bash
# Test installation
curl -fsSL https://raw.githubusercontent.com/k4lantar4/moonfrp/main/install.sh | bash

# Test server setup
moonfrp setup server

# Test client setup
moonfrp setup client

# Test service management
moonfrp service start all
moonfrp health check
```

## 🔧 Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   sudo moonfrp
   ```

2. **Service Won't Start**
   ```bash
   # Check logs
   moonfrp service logs moonfrp-server
   
   # Check configuration
   moonfrp config validate
   ```

3. **Port Already in Use**
   ```bash
   # Check what's using the port
   netstat -tlnp | grep :7000
   
   # Kill the process
   sudo kill -9 <PID>
   ```

4. **Connection Refused**
   ```bash
   # Check firewall
   sudo ufw status
   sudo ufw allow 7000/tcp
   
   # Check if service is running
   moonfrp service status
   ```

### Debug Mode

Enable debug logging by editing the configuration:

```bash
# Edit configuration
sudo nano /etc/moonfrp/config

# Set debug level
MOONFRP_LOG_LEVEL="debug"

# Restart services
moonfrp service restart all
```

## 📋 Requirements

### System Requirements

- **OS**: Ubuntu 22.04 LTS (recommended), Ubuntu 20.04+, Debian 10+
- **Architecture**: x86_64 (amd64), ARM64, ARMv7
- **Memory**: Minimum 512MB RAM
- **Storage**: 100MB free space
- **Network**: Internet connection for installation

### Dependencies

- `curl` - For downloading files
- `tar` - For extracting archives
- `systemctl` - For service management
- `openssl` - For token generation

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Development Setup

```bash
# Clone the repository
git clone https://github.com/k4lantar4/moonfrp.git
cd moonfrp

# Make scripts executable
chmod +x *.sh

# Test locally
sudo ./moonfrp.sh
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/k4lantar4/moonfrp/issues)
- **Discussions**: [GitHub Discussions](https://github.com/k4lantar4/moonfrp/discussions)
- **Documentation**: [Wiki](https://github.com/k4lantar4/moonfrp/wiki)

## 📝 Changelog

### Version 2.0.0 (2025-01-26)

- ✨ **Complete Rewrite**: Modular architecture with clean separation of concerns
- 🚀 **One-Command Installation**: True one-command installation with environment variable support
- 🔧 **Environment Variables**: All settings configurable via environment variables
- 📊 **Professional Service Management**: Enhanced systemd integration with health monitoring
- 🎯 **Simplified UI**: Clean, intuitive interface with command-line support
- 🔍 **Comprehensive Testing**: Full test suite for fresh server deployment
- 📚 **Enhanced Documentation**: Complete documentation with examples
- ⚡ **Performance Optimized**: Improved performance and resource usage
- 🛡️ **Security Enhanced**: Security-first configuration with secure defaults

### Version 1.1.1 (Previous)

- Initial release with basic functionality
- Single monolithic script
- Basic service management
- Limited configuration options

## 🗺️ Roadmap

- [ ] Web-based management interface
- [ ] Docker support
- [ ] Configuration templates
- [ ] Backup and restore functionality
- [ ] Monitoring and alerting
- [ ] Auto-update mechanism
- [ ] Plugin system
- [ ] Multi-language support

## 🙏 Acknowledgments

- [fatedier/frp](https://github.com/fatedier/frp) - The amazing FRP project
- [MVTunnel Project](https://github.com/k4lantar4/moonfrp) - Inspiration for this tool
- All contributors and users of MoonFRP

---

**Made with ❤️ by the MoonFRP Team**

*"Simplifying FRP management, one configuration at a time."*