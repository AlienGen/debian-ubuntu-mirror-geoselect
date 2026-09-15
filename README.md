# Debian/Ubuntu Mirror Auto-Selection Script based on geographical location

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-green.svg)](https://www.debian.org/)

A smart, automated script that detects your geographical location and configures the most appropriate Debian/Ubuntu package mirrors for optimal download speeds. Perfect for Docker builds, CI/CD pipelines, and system administration.

## 🌟 Features

- **🌍 Automatic Geographical Detection** - IP geolocation with multiple HTTP transports
- **🚀 Optimized Mirrors** - Pre-configured fast mirrors for China, Japan, Korea, and other regions
- **🔄 Deep Fallback Chain** - Transport, offline heuristics, and ordered mirror candidates
- **🛡️ Safe Execution** - Creates automatic backups before making changes
- **📊 Comprehensive Logging** - Colored output with detailed progress information
- **🔧 Multi-Distribution Support** - Works with both Debian and Ubuntu systems
- **⚡ Speed Testing** - Optional `apt-get download` mirror speed testing

## 🎯 Perfect For

- **Docker Builds** - Optimize package downloads in container builds
- **CI/CD Pipelines** - Faster builds in automated environments
- **System Administration** - Quick mirror optimization for servers
- **Development Environments** - Faster package installation for developers
- **International Teams** - Works optimally from any location worldwide

## 📋 Requirements

- **Operating System**: Debian, Ubuntu, or compatible distributions
- **Shell**: `bash`
- **Permissions**: Root access (for writing to `/etc/apt/sources.list`)
- **Network**: Internet connectivity for geolocation and `apt-get update`
- **Geolocation transports** (first available wins): `curl`, `wget`, `openssl` (HTTPS), or bash `/dev/tcp` (HTTP)
- **Note**: `debian:*-slim` / `ubuntu:*-slim` images usually **do not** ship `curl` or `wget`. The script can still geolocate via `openssl` (typically present) or HTTP `/dev/tcp`, then fall back to timezone/`LANG` heuristics.

### How location and mirrors are chosen

1. `FORCE_COUNTRY` if set
2. HTTP geo APIs via `curl` → `wget` → `openssl s_client` → bash `/dev/tcp`
3. Offline heuristics from `TZ` / `/etc/timezone` / locale
4. Default `US`
5. For the chosen region: try primary mirror → alternate (when defined) → official CDN until `apt-get update` succeeds

## 🚀 Quick Start

### One-Liner Installation & Execution

For servers or CI images that already have `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/AlienGen/debian-ubuntu-mirror-geoselect/main/auto-select-mirror.sh | sudo bash
```

### Dockerfile Integration

**Important:** slim base images do not include `curl`, so a bare `RUN curl ... | bash` will fail until curl is installed (or you COPY/`ADD` the script).

#### Option A — COPY the script (recommended, no curl needed to fetch)

```dockerfile
FROM debian:bookworm-slim
COPY auto-select-mirror.sh /auto-select-mirror.sh
RUN chmod +x /auto-select-mirror.sh && /auto-select-mirror.sh
```

Geolocation still works without curl (openssl / heuristics). To pin a region:

```dockerfile
RUN FORCE_COUNTRY=CN /auto-select-mirror.sh
```

#### Option B — `ADD` remote URL (fetch without curl in the image)

```dockerfile
FROM debian:bookworm-slim
ADD https://raw.githubusercontent.com/AlienGen/debian-ubuntu-mirror-geoselect/main/auto-select-mirror.sh /auto-select-mirror.sh
RUN chmod +x /auto-select-mirror.sh && /auto-select-mirror.sh
```

#### Option C — Bootstrap curl, then one-liner

```dockerfile
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
 && curl -fsSL https://raw.githubusercontent.com/AlienGen/debian-ubuntu-mirror-geoselect/main/auto-select-mirror.sh | bash \
 && apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
```

### CI/CD Pipeline Integration

```yaml
# GitHub Actions
- name: Optimize package mirrors
  run: curl -fsSL https://raw.githubusercontent.com/AlienGen/debian-ubuntu-mirror-geoselect/main/auto-select-mirror.sh | sudo bash

# GitLab CI
mirror_optimization:
  script:
    - curl -fsSL https://raw.githubusercontent.com/AlienGen/debian-ubuntu-mirror-geoselect/main/auto-select-mirror.sh | bash

# Jenkins Pipeline
stage('Optimize Mirrors') {
    steps {
        sh 'curl -fsSL https://raw.githubusercontent.com/AlienGen/debian-ubuntu-mirror-geoselect/main/auto-select-mirror.sh | sudo bash'
    }
}
```

### 1. Download the Script

```bash
# Download directly
curl -O https://raw.githubusercontent.com/AlienGen/debian-ubuntu-mirror-geoselect/main/auto-select-mirror.sh

# Or clone the repository
git clone https://github.com/AlienGen/debian-ubuntu-mirror-geoselect.git
cd debian-ubuntu-mirror-geoselect
```

### 2. Make it Executable

```bash
chmod +x auto-select-mirror.sh
```

### 3. Run the Script

```bash
# Run with sudo (recommended)
sudo ./auto-select-mirror.sh

# Or run as root
sudo su -
./auto-select-mirror.sh
```

## 📖 Usage Examples

### Basic Usage

```bash
sudo ./auto-select-mirror.sh
```

**Output:**
```
[INFO] Starting mirror auto-selection...
[INFO] Detected: debian 12 (bookworm)
[WARNING] No existing /etc/apt/sources.list found - this is normal in some Docker images
[INFO] No .list files found in sources.list.d
[INFO] Thoroughly cleaning APT sources...
[INFO] Searching for all APT sources locations...
[INFO] Found: /etc/apt/sources.list.d/
[INFO]   - /etc/apt/sources.list.d//debian.sources
[INFO] Found: /var/lib/apt/lists/
[INFO] Found: /etc/apt/apt.conf.d/
[INFO]   - /etc/apt/apt.conf.d//01autoremove
[INFO]   - /etc/apt/apt.conf.d//70debconf
[INFO]   - /etc/apt/apt.conf.d//docker-autoremove-suggests
[INFO]   - /etc/apt/apt.conf.d//docker-clean
[INFO]   - /etc/apt/apt.conf.d//docker-gzip-indexes
[INFO]   - /etc/apt/apt.conf.d//docker-no-languages
[INFO] Searching for files containing mirror references...
[INFO] Found mirror reference in: /etc/apt/sources.list.d/debian.sources
[INFO] Removing all sources.list.d files...
[INFO] Checking APT configuration files...
[SUCCESS] APT sources cleaned
[INFO] Detecting geographical location...
[INFO] Trying service: https://ipapi.co/country_code
[SUCCESS] Location detected: CN
[INFO] Selecting mirrors for CN...
[INFO] Using Chinese mirrors (Tsinghua University)
[INFO] Writing new sources.list...
[SUCCESS] Sources.list written successfully
[INFO] Contents preview:
  deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
  deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
  deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
[INFO] Updating package lists...
Get:1 https://mirrors.tuna.tsinghua.edu.cn/debian bookworm InRelease [151 kB]
Get:2 https://mirrors.tuna.tsinghua.edu.cn/debian bookworm-updates InRelease [55.4 kB]
Get:3 https://mirrors.tuna.tsinghua.edu.cn/debian bookworm-backports InRelease [59.4 kB]
Get:4 https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security InRelease [48.0 kB]
Get:5 https://mirrors.tuna.tsinghua.edu.cn/debian bookworm/non-free amd64 Packages [102 kB]
Get:6 https://mirrors.tuna.tsinghua.edu.cn/debian bookworm/non-free-firmware amd64 Packages [6372 B]
Get:7 https://mirrors.tuna.tsinghua.edu.cn/debian bookworm/main amd64 Packages [8793 kB]
Get:8 https://mirrors.tuna.tsinghua.edu.cn/debian bookworm/contrib amd64 Packages [53.5 kB]
Get:9 https://mirrors.tuna.tsinghua.edu.cn/debian bookworm-updates/main amd64 Packages [756 B]
Get:10 https://mirrors.tuna.tsinghua.edu.cn/debian bookworm-backports/main amd64 Packages [291 kB]
Get:11 https://mirrors.tuna.tsinghua.edu.cn/debian bookworm-backports/non-free-firmware amd64 Packages [3828 B]
Get:12 https://mirrors.tuna.tsinghua.edu.cn/debian bookworm-backports/contrib amd64 Packages [5852 B]
Get:13 https://mirrors.tuna.tsinghua.edu.cn/debian bookworm-backports/non-free amd64 Packages [13.3 kB]
Get:14 https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security/main amd64 Packages [268 kB]
Get:15 https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security/non-free-firmware amd64 Packages [688 B]
Get:16 https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security/contrib amd64 Packages [896 B]
Fetched 9852 kB in 3s (3479 kB/s)
Reading package lists...
[SUCCESS] Package lists updated successfully
[SUCCESS] Mirror configuration completed successfully!
[INFO] Testing mirror speed...
[SUCCESS] Mirror test completed in 1s
[INFO] You can now use 'apt-get update' and 'apt-get install' with optimized mirrors
```

### Docker Integration

See [Dockerfile Integration](#dockerfile-integration) above for COPY, `ADD`, and curl-bootstrap recipes. Slim images lack `curl`/`wget` by default.

## 🌍 Supported Regions

The script automatically selects the best mirrors based on your detected location:

| Region | Countries | Mirror Provider | Speed |
|--------|-----------|-----------------|-------|
| **China** | CN, HK, TW, MO | Tsinghua University | ⚡⚡⚡⚡⚡ |
| **Japan/Korea** | JP, KR | Japanese Debian | ⚡⚡⚡⚡ |
| **Southeast Asia** | SG, MY, TH, VN, ID, PH | Singapore Debian | ⚡⚡⚡⚡ |
| **Australia/NZ** | AU, NZ | Australian Debian | ⚡⚡⚡ |
| **UK/Ireland** | GB, IE | UK Debian | ⚡⚡⚡ |
| **Europe** | DE, AT, CH, NL, BE, FR, IT, ES, PT | Official Debian | ⚡⚡⚡ |
| **Rest of World** | All others | US Debian | ⚡⚡ |

## 🔧 Configuration

### Environment Variables

You can customize the script behavior with environment variables:

```bash
# Force a specific country (bypasses geolocation)
export FORCE_COUNTRY=CN
sudo ./auto-select-mirror.sh

# Disable speed testing
export DISABLE_SPEED_TEST=1
sudo ./auto-select-mirror.sh
```

### Custom Mirror Configuration

To add custom mirrors for your region, edit the `get_mirror_candidates()` function in the script and append candidates with `add_debian_candidate` / `add_ubuntu_candidate` (primary first, CDN last).

## 🛠️ Troubleshooting

### Common Issues

#### 1. Permission Denied
```bash
[ERROR] This script must be run as root (use sudo)
```
**Solution:** Run with `sudo ./auto-select-mirror.sh`

#### 2. Geolocation Detection Fails
```bash
[WARNING] Geolocation detection failed, using default (US)
```
**Solution:** Check your internet connection or use `FORCE_COUNTRY` environment variable

#### 3. Mirror Update Fails
```bash
[ERROR] Failed to update package lists
```
**Solution:** The script automatically restores your backup. Check your network connection.

#### 4. Curl / wget not in slim images
```bash
[INFO] curl/wget not available; using openssl for HTTPS geolocation
```
or
```bash
[WARNING] curl/wget/openssl not available; will try HTTP /dev/tcp and offline heuristics
```
**Solution:** No install required in most cases — the script falls back to `openssl`, HTTP `/dev/tcp`, then timezone/`LANG`. To force a region: `FORCE_COUNTRY=CN`. To fetch the script itself into a slim image, use `COPY`, Docker `ADD` of the raw URL, or install curl temporarily (see Dockerfile options above).

### Debug Mode

Enable verbose output for troubleshooting:

```bash
export DEBUG=1
# Run with debug output
bash ./auto-select-mirror.sh
```

### Manual Backup Restoration

If you need to restore your original sources.list:

```bash
# List available backups
ls -la /etc/apt/sources.list.backup.*

# Restore a specific backup
sudo cp /etc/apt/sources.list.backup.20250621_143022 /etc/apt/sources.list
```

## 📊 Performance Comparison

Typical speed improvements by region:

| Region | Default Speed | Optimized Speed | Improvement |
|--------|---------------|-----------------|-------------|
| China | 50 KB/s | 5 MB/s | **100x faster** |
| Japan | 500 KB/s | 10 MB/s | **20x faster** |
| Europe | 2 MB/s | 8 MB/s | **4x faster** |
| US | 5 MB/s | 8 MB/s | **1.6x faster** |

## 🔒 Security

- **Backup Creation**: Automatic backup before any changes
- **Error Handling**: Graceful fallback on failures
- **Input Validation**: Sanitized inputs and outputs
- **Minimal Dependencies**: Geolocation works with curl, wget, openssl, or bash `/dev/tcp`
- **Open Source**: Full transparency of all operations

## 🤝 Contributing

We welcome contributions! Please feel free to:

1. **Fork** the repository
2. **Create** a feature branch
3. **Add** your improvements
4. **Test** thoroughly
5. **Submit** a pull request

### Development Setup

```bash
# Clone the repository
git clone https://github.com/AlienGen/debian-ubuntu-mirror-geoselect.git
cd debian-ubuntu-mirror-geoselect

# Make changes and test
./auto-select-mirror.sh
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Tsinghua University** for providing excellent mirrors in China
- **Debian Project** for maintaining the official mirrors
- **Ubuntu Project** for their mirror infrastructure
- **Open Source Community** for feedback and contributions

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/AlienGen/debian-ubuntu-mirror-geoselect/issues)
- **Website** [AlienGen](https://www.aliengen.com)
- **Email**: opensource@aliengen.com

## 📈 Version History

- **v1.1.0** (2026-09-15)
  - Fix false-positive failure when using official `deb.debian.org` / `archive.ubuntu.com` mirrors
  - HTTP transport fallbacks: curl → wget → openssl → `/dev/tcp`
  - Offline location heuristics from timezone and locale
  - Ordered mirror candidates with `apt-get update` verification
  - Clearer Docker slim-image documentation
- **v1.0.0** (2025-06-21)
  - Initial release
  - Support for Debian and Ubuntu
  - Automatic geolocation detection
  - Regional mirror optimization
  - Comprehensive error handling

---

**Made with ❤️ by the AlienGen Team**

*Optimizing infrastructure worldwide, one server at a time.* 