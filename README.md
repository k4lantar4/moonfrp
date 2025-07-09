# MoonFRP 🌙

**Advanced FRP Management Tool** - A powerful, modular bash script for managing FRP (Fast Reverse Proxy) configurations and services with ease.

## Features ✨

- **🚀 One-Command Installation**: Install via curl command
- **🔧 Modular Configuration**: Separate Iran server and foreign client configurations
- **📊 Service Management**: Complete systemd service lifecycle management
- **🔄 Multi-IP Support**: Support for multiple Iran server IPs with automatic port mapping
- **🛡️ Security First**: Token-based authentication and TLS encryption
- **📱 Interactive UI**: Beautiful colored menus with user-friendly navigation
- **🔍 Comprehensive Logging**: Detailed logging for debugging and monitoring
- **⚡ Auto-Recovery**: Automatic service restart and error handling
- **🎯 Smart Validation**: Input validation for IPs, ports, and configurations

## Quick Installation 🚀

### Ubuntu 22.04 LTS (One-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/moonfrp/install.sh/main/install.sh | sudo bash
```

### Manual Installation

```bash
# Download the script
wget https://raw.githubusercontent.com/moonfrp/install.sh/main/moonfrp.sh

# Make it executable
chmod +x moonfrp.sh

# Move to system path
sudo mv moonfrp.sh /usr/local/bin/moonfrp

# Create symlink (optional)
sudo ln -sf /usr/local/bin/moonfrp /usr/bin/mv
```

## Usage 🎯

### Start MoonFRP

```bash
# Using the command
moonfrp

# Or if symlink was created
mv
```

### Main Menu Options

```
╔══════════════════════════════════════╗
║            MoonFRP                   ║
║    Advanced FRP Management Tool     ║
║          Version 1.0.0              ║
╚══════════════════════════════════════╝

Main Menu:
1. Create FRP Configuration
2. Service Management
3. Download & Install FRP v0.63.0
4. Install from Local Archive
5. Remove Services
0. Exit
```

## Configuration Examples 📋

### 1. Iran Server Configuration

When you select **Iran** configuration:

```toml
# Generated frps.toml
bindAddr = "0.0.0.0"
bindPort = 7000

auth.method = "token"
auth.token = "your-secure-token"

webServer.addr = "0.0.0.0"
webServer.port = 7500
webServer.user = "admin"
webServer.password = "admin123"

log.to = "/var/log/frp/frps.log"
log.level = "info"
log.maxDays = 7

transport.tls.enable = true
transport.maxPoolCount = 10
```

### 2. Foreign Client Configuration

For multiple Iran server IPs: `1.1.1.1,2.2.2.2,3.3.3.3,4.4.4.4`
With ports: `1111,2222,3333,4444`

This creates 4 separate configurations:
- `frpc_1.toml` for IP ending with 1
- `frpc_2.toml` for IP ending with 2
- `frpc_3.toml` for IP ending with 3
- `frpc_4.toml` for IP ending with 4

Each configuration includes:

```toml
# Generated frpc_1.toml (example)
serverAddr = "1.1.1.1"
serverPort = 7000

auth.method = "token"
auth.token = "your-secure-token"

transport.tls.enable = true
transport.poolCount = 5
transport.protocol = "tcp"

user = "moonfrp_1"

[[proxies]]
name = "tcp_1111_1"
type = "tcp"
localIP = "127.0.0.1"
localPort = 1111
remotePort = 1111

[[proxies]]
name = "tcp_2222_1"
type = "tcp"
localIP = "127.0.0.1"
localPort = 2222
remotePort = 2222
```

## Service Management 🔧

### Automatic Service Creation

MoonFRP automatically creates systemd services:

- **Server**: `moonfrp-server.service`
- **Clients**: `moonfrp-client-1.service`, `moonfrp-client-2.service`, etc.

### Service Operations

```bash
# View service status
systemctl status moonfrp-server

# Start/Stop services
systemctl start moonfrp-client-1
systemctl stop moonfrp-client-1

# View logs
journalctl -u moonfrp-server -f

# Enable/Disable auto-start
systemctl enable moonfrp-server
systemctl disable moonfrp-server
```

## File Structure 📁

```
/opt/frp/                    # FRP binaries
├── frps                     # FRP server binary
└── frpc                     # FRP client binary

/etc/frp/                    # Configuration files
├── frps.toml               # Server configuration
├── frpc_1.toml             # Client configuration for IP suffix 1
├── frpc_2.toml             # Client configuration for IP suffix 2
└── ...

/var/log/frp/               # Log files
├── moonfrp.log             # MoonFRP script logs
├── frps.log                # Server logs
├── frpc_1.log              # Client logs
└── ...

/etc/systemd/system/        # Systemd service files
├── moonfrp-server.service
├── moonfrp-client-1.service
└── ...
```

## Advanced Features 🔥

### 1. Multi-IP Load Balancing

Configure multiple Iran server IPs for load balancing and redundancy:

```bash
# Input example
Iran Server IPs: 1.1.1.1,2.2.2.2,3.3.3.3,4.4.4.4
Ports: 1111,2222,3333,4444
```

### 2. Service Health Monitoring

Built-in health checking and automatic restart:

```toml
# Health check configuration
healthCheck.type = "tcp"
healthCheck.timeoutSeconds = 3
healthCheck.maxFailed = 3
healthCheck.intervalSeconds = 10
```

### 3. Security Features

- **Token Authentication**: Secure token-based authentication
- **TLS Encryption**: End-to-end TLS encryption
- **Port Restrictions**: Configurable allowed port ranges
- **User Isolation**: Separate user namespaces for clients

### 4. Performance Optimization

- **Connection Pooling**: Pre-established connection pools
- **Compression**: Optional traffic compression
- **Bandwidth Limiting**: Per-proxy bandwidth controls
- **Multiplexing**: TCP connection multiplexing

## Troubleshooting 🔧

### Common Issues

1. **Permission Denied**
   ```bash
   sudo moonfrp
   ```

2. **Service Won't Start**
   ```bash
   # Check logs
   journalctl -u moonfrp-server -n 50
   
   # Check configuration
   /opt/frp/frps -c /etc/frp/frps.toml -v
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
   systemctl status moonfrp-server
   ```

### Debug Mode

Enable debug logging by editing the configuration:

```toml
log.level = "debug"
```

## Requirements 📋

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

## Contributing 🤝

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Development Setup

```bash
# Clone the repository
git clone https://github.com/moonfrp/install.sh.git
cd install.sh

# Make scripts executable
chmod +x moonfrp.sh install.sh

# Test locally
sudo ./moonfrp.sh
```

## License 📄

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support 💬

- **Issues**: [GitHub Issues](https://github.com/moonfrp/install.sh/issues)
- **Discussions**: [GitHub Discussions](https://github.com/moonfrp/install.sh/discussions)
- **Documentation**: [Wiki](https://github.com/moonfrp/install.sh/wiki)

## Changelog 📝

### Version 1.0.0 (2025-01-XX)

- ✨ Initial release
- 🚀 One-command installation
- 🔧 Interactive configuration wizard
- 📊 Complete service management
- 🔄 Multi-IP support
- 🛡️ Security features
- 📱 Beautiful UI with colors
- 🔍 Comprehensive logging

## Roadmap 🗺️

- [ ] Web-based management interface
- [ ] Docker support
- [ ] Configuration templates
- [ ] Backup and restore functionality
- [ ] Monitoring and alerting
- [ ] Auto-update mechanism
- [ ] Plugin system
- [ ] Multi-language support

## Acknowledgments 🙏

- [fatedier/frp](https://github.com/fatedier/frp) - The amazing FRP project
- [MVTunnel Project](https://github.com/moonfrp) - Inspiration for this tool
- All contributors and users of MoonFRP

---

**Made with ❤️ by the MoonFRP Team**

*"Simplifying FRP management, one configuration at a time."* 