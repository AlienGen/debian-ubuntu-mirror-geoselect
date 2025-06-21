#!/bin/bash

# =============================================================================
# Debian/Ubuntu Mirror Auto-Selection Script
# =============================================================================
#
# This script automatically detects the user's geographical location and
# configures the most appropriate Debian/Ubuntu package mirrors for optimal
# download speeds.
#
# Features:
# - Automatic geographical detection using IP geolocation
# - Optimized mirrors for China, Japan, Korea, and other regions
# - Fallback to reliable default mirrors if detection fails
# - Support for both Debian and Ubuntu systems
# - Comprehensive error handling and logging
# - Safe execution with backup creation
#
# Usage:
#   ./auto-select-mirror.sh
#   sudo ./auto-select-mirror.sh
#
# Requirements:
#   - curl (for IP geolocation)
#   - Internet connectivity
#   - Root privileges (for writing to /etc/apt/sources.list)
#
# Author: AlienGen Team
# License: MIT License
# Version: 1.0.0
# Last Updated: 2025
#
# =============================================================================

# Use compatible error handling for different shell environments
set -e  # Exit on error

# If debug is not set, set it to 0
if [ -z "$DEBUG" ]; then
    DEBUG=0
fi

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to detect Debian/Ubuntu version
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_NAME="$ID"
        DISTRO_VERSION="$VERSION_ID"
        DISTRO_CODENAME="$VERSION_CODENAME"
    elif [ -f /etc/debian_version ]; then
        DISTRO_NAME="debian"
        DISTRO_VERSION=$(cat /etc/debian_version)
        # Map Debian version to codename
        case "$DISTRO_VERSION" in
            "12"*) DISTRO_CODENAME="bookworm" ;;
            "11"*) DISTRO_CODENAME="bullseye" ;;
            "10"*) DISTRO_CODENAME="buster" ;;
            *) DISTRO_CODENAME="bookworm" ;; # Default to latest
        esac
    else
        log_error "Unable to detect distribution"
        exit 1
    fi
    
    log_info "Detected: $DISTRO_NAME $DISTRO_VERSION ($DISTRO_CODENAME)"
}

# Function to detect geographical location
detect_location() {
    # If the FORCE_COUNTRY is set, use it instead of auto-detecting
    if [ -n "$FORCE_COUNTRY" ]; then
        log_info "Forcing country $FORCE_COUNTRY"
        echo "$FORCE_COUNTRY"
        return
    fi

    log_info "Detecting geographical location..."
    
    # Try multiple geolocation services for reliability
    local country=""
    local services=(
        "https://ipapi.co/country_code"
        "https://ipinfo.io/country"
        "https://ifconfig.me/country-iso"
    )
    
    for service in "${services[@]}"; do
        if command -v curl >/dev/null 2>&1; then
            log_info "Trying service: $service"
            country=$(curl -s --max-time 10 --retry 2 "$service" 2>/dev/null | tr -d '\r\n')
            
            if [ -n "$country" ] && [ "$country" != "null" ] && [ "$country" != "undefined" ]; then
                log_success "Location detected: $country"
                break
            fi
        fi
    done
    
    # Fallback to default if detection fails
    if [ -z "$country" ] || [ "$country" = "null" ] || [ "$country" = "undefined" ]; then
        log_warning "Geolocation detection failed, using default (US)"
        country="US"
    fi
    
    echo "$country"
}

# Function to get appropriate mirrors for the detected location
get_mirrors() {
    local country="$1"
    local distro="$2"
    local codename="$3"
    
    log_info "Selecting mirrors for $country..." >&2
    
    case "$country" in
        CN|HK|TW|MO)
            # China and nearby regions - use Tsinghua University mirrors
            log_info "Using Chinese mirrors (Tsinghua University)" >&2
            if [ "$distro" = "debian" ]; then
                cat << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $codename main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $codename-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $codename-backports main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security $codename-security main contrib non-free non-free-firmware
EOF
            elif [ "$distro" = "ubuntu" ]; then
                cat << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $codename main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $codename-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $codename-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $codename-security main restricted universe multiverse
EOF
            fi
            ;;
        JP|KR)
            # Japan/Korea - use Japanese mirrors
            log_info "Using Japanese mirrors" >&2
            if [ "$distro" = "debian" ]; then
                cat << EOF
deb https://ftp.jp.debian.org/debian/ $codename main contrib non-free non-free-firmware
deb https://ftp.jp.debian.org/debian/ $codename-updates main contrib non-free non-free-firmware
deb https://ftp.jp.debian.org/debian/ $codename-backports main contrib non-free non-free-firmware
deb https://security.debian.org/debian-security $codename-security main contrib non-free non-free-firmware
EOF
            elif [ "$distro" = "ubuntu" ]; then
                cat << EOF
deb https://jp.archive.ubuntu.com/ubuntu/ $codename main restricted universe multiverse
deb https://jp.archive.ubuntu.com/ubuntu/ $codename-updates main restricted universe multiverse
deb https://jp.archive.ubuntu.com/ubuntu/ $codename-backports main restricted universe multiverse
deb https://jp.archive.ubuntu.com/ubuntu/ $codename-security main restricted universe multiverse
EOF
            fi
            ;;
        SG|MY|TH|VN|ID|PH)
            # Southeast Asia - use Singapore mirrors
            log_info "Using Singapore mirrors" >&2
            if [ "$distro" = "debian" ]; then
                cat << EOF
deb https://ftp.sg.debian.org/debian/ $codename main contrib non-free non-free-firmware
deb https://ftp.sg.debian.org/debian/ $codename-updates main contrib non-free non-free-firmware
deb https://ftp.sg.debian.org/debian/ $codename-backports main contrib non-free non-free-firmware
deb https://security.debian.org/debian-security $codename-security main contrib non-free non-free-firmware
EOF
            elif [ "$distro" = "ubuntu" ]; then
                cat << EOF
deb https://sg.archive.ubuntu.com/ubuntu/ $codename main restricted universe multiverse
deb https://sg.archive.ubuntu.com/ubuntu/ $codename-updates main restricted universe multiverse
deb https://sg.archive.ubuntu.com/ubuntu/ $codename-backports main restricted universe multiverse
deb https://sg.archive.ubuntu.com/ubuntu/ $codename-security main restricted universe multiverse
EOF
            fi
            ;;
        AU|NZ)
            # Australia/New Zealand
            log_info "Using Australian mirrors" >&2
            if [ "$distro" = "debian" ]; then
                cat << EOF
deb https://ftp.au.debian.org/debian/ $codename main contrib non-free non-free-firmware
deb https://ftp.au.debian.org/debian/ $codename-updates main contrib non-free non-free-firmware
deb https://ftp.au.debian.org/debian/ $codename-backports main contrib non-free non-free-firmware
deb https://security.debian.org/debian-security $codename-security main contrib non-free non-free-firmware
EOF
            elif [ "$distro" = "ubuntu" ]; then
                cat << EOF
deb https://au.archive.ubuntu.com/ubuntu/ $codename main restricted universe multiverse
deb https://au.archive.ubuntu.com/ubuntu/ $codename-updates main restricted universe multiverse
deb https://au.archive.ubuntu.com/ubuntu/ $codename-backports main restricted universe multiverse
deb https://au.archive.ubuntu.com/ubuntu/ $codename-security main restricted universe multiverse
EOF
            fi
            ;;
        GB|IE)
            # United Kingdom/Ireland
            log_info "Using UK mirrors" >&2
            if [ "$distro" = "debian" ]; then
                cat << EOF
deb https://ftp.uk.debian.org/debian/ $codename main contrib non-free non-free-firmware
deb https://ftp.uk.debian.org/debian/ $codename-updates main contrib non-free non-free-firmware
deb https://ftp.uk.debian.org/debian/ $codename-backports main contrib non-free non-free-firmware
deb https://security.debian.org/debian-security $codename-security main contrib non-free non-free-firmware
EOF
            elif [ "$distro" = "ubuntu" ]; then
                cat << EOF
deb https://gb.archive.ubuntu.com/ubuntu/ $codename main restricted universe multiverse
deb https://gb.archive.ubuntu.com/ubuntu/ $codename-updates main restricted universe multiverse
deb https://gb.archive.ubuntu.com/ubuntu/ $codename-backports main restricted universe multiverse
deb https://gb.archive.ubuntu.com/ubuntu/ $codename-security main restricted universe multiverse
EOF
            fi
            ;;
        DE|AT|CH|NL|BE|FR|IT|ES|PT)
            # European countries
            log_info "Using European mirrors" >&2
            if [ "$distro" = "debian" ]; then
                cat << EOF
deb https://deb.debian.org/debian/ $codename main contrib non-free non-free-firmware
deb https://deb.debian.org/debian/ $codename-updates main contrib non-free non-free-firmware
deb https://deb.debian.org/debian/ $codename-backports main contrib non-free non-free-firmware
deb https://security.debian.org/debian-security $codename-security main contrib non-free non-free-firmware
EOF
            elif [ "$distro" = "ubuntu" ]; then
                cat << EOF
deb https://archive.ubuntu.com/ubuntu/ $codename main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/ $codename-updates main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/ $codename-backports main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/ $codename-security main restricted universe multiverse
EOF
            fi
            ;;
        *)
            # Default to US mirrors for other regions
            log_info "Using US mirrors (default)" >&2
            if [ "$distro" = "debian" ]; then
                cat << EOF
deb https://deb.debian.org/debian/ $codename main contrib non-free non-free-firmware
deb https://deb.debian.org/debian/ $codename-updates main contrib non-free non-free-firmware
deb https://deb.debian.org/debian/ $codename-backports main contrib non-free non-free-firmware
deb https://security.debian.org/debian-security $codename-security main contrib non-free non-free-firmware
EOF
            elif [ "$distro" = "ubuntu" ]; then
                cat << EOF
deb https://us.archive.ubuntu.com/ubuntu/ $codename main restricted universe multiverse
deb https://us.archive.ubuntu.com/ubuntu/ $codename-updates main restricted universe multiverse
deb https://us.archive.ubuntu.com/ubuntu/ $codename-backports main restricted universe multiverse
deb https://us.archive.ubuntu.com/ubuntu/ $codename-security main restricted universe multiverse
EOF
            fi
            ;;
    esac
}

# Function to backup current sources
backup_sources() {
    local backup_file="/etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S)"
    local sources_backup_dir="/etc/apt/sources.list.d.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup directory
    mkdir -p "$sources_backup_dir"
    
    # Check and backup main sources.list
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list "$backup_file"
        log_success "Backup created: $backup_file"
    else
        log_warning "No existing /etc/apt/sources.list found - this is normal in some Docker images"
        # Create an empty backup file to track that we made a backup
        touch "$backup_file"
    fi
    
    # Check and backup sources.list.d directory
    if [ -d /etc/apt/sources.list.d ]; then
        local file_count=0
        for file in /etc/apt/sources.list.d/*.list; do
            if [ -f "$file" ]; then
                cp "$file" "$sources_backup_dir/"
                file_count=$((file_count + 1))
            fi
        done
        
        if [ $file_count -gt 0 ]; then
            log_success "Backed up $file_count files from sources.list.d to $sources_backup_dir"
        else
            log_info "No .list files found in sources.list.d"
        fi
    else
        log_info "No sources.list.d directory found"
    fi
    
    # Check if we have any sources at all
    if [ ! -f /etc/apt/sources.list ] && [ ! -d /etc/apt/sources.list.d ]; then
        log_warning "No APT sources found - this might be a minimal Docker image"
    fi
}

# Function to find all APT sources locations
find_all_apt_sources() {
    log_info "Searching for all APT sources locations..."
    
    local found_sources=()
    
    # Check common sources locations
    local possible_locations=(
        "/etc/apt/sources.list"
        "/etc/apt/sources.list.d/"
        "/etc/apt/sources.list.save"
        "/etc/apt/sources.list.d.save"
        "/var/lib/apt/lists/"
        "/usr/share/apt/apt.conf.d/"
        "/etc/apt/apt.conf.d/"
        "/etc/apt/apt.conf"
        "/etc/apt/apt.conf.d/99mirrors"
        "/etc/apt/apt.conf.d/99default-release"
    )
    
    for location in "${possible_locations[@]}"; do
        if [ -e "$location" ]; then
            found_sources+=("$location")
            log_info "Found: $location"
            
            # If it's a directory, list its contents
            if [ -d "$location" ]; then
                for file in "$location"/*; do
                    if [ -f "$file" ]; then
                        log_info "  - $file"
                        found_sources+=("$file")
                    fi
                done
            fi
        fi
    done
    
    # Search for any files containing mirror references
    log_info "Searching for files containing mirror references..."
    local mirror_files=$(find /etc -name "*.list" -o -name "*.conf" -o -name "sources*" -o -name "*.sources" 2>/dev/null | grep -E "(apt|sources)" || true)
    
    for file in $mirror_files; do
        if [ -f "$file" ] && grep -q "deb\.debian\.org\|archive\.ubuntu.com" "$file" 2>/dev/null; then
            log_info "Found mirror reference in: $file"
            found_sources+=("$file")
        fi
    done
    
    # Check for any environment variables or build-time configurations
    if [ -n "$APT_SOURCES" ]; then
        log_info "Found APT_SOURCES environment variable"
        found_sources+=("APT_SOURCES_ENV")
    fi
    
    echo "${found_sources[@]}"
}

# Function to thoroughly clean APT sources
clean_apt_sources() {
    log_info "Thoroughly cleaning APT sources..."
    
    # Find all sources locations first
    local all_sources=($(find_all_apt_sources))
    
    # Clear APT cache
    apt-get clean 2>/dev/null || true
    rm -rf /var/lib/apt/lists/* 2>/dev/null || true
    
    # Remove all sources.list.d files (including .sources files)
    if [ -d /etc/apt/sources.list.d ]; then
        log_info "Removing all sources.list.d files..."
        rm -f /etc/apt/sources.list.d/*.list 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/*.save 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/*.conf 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/*.sources 2>/dev/null || true
    fi
    
    # Clear any existing sources.list
    if [ -f /etc/apt/sources.list ]; then
        log_info "Clearing existing sources.list..."
        rm -f /etc/apt/sources.list
    fi
    
    # Remove any .save files
    rm -f /etc/apt/sources.list.save 2>/dev/null || true
    rm -rf /etc/apt/sources.list.d.save 2>/dev/null || true
    
    # Check for any other potential sources files
    local other_sources=(
        "/etc/apt/sources.list.save"
        "/etc/apt/sources.list.d.save"
        "/var/lib/apt/lists/deb.debian.org*"
        "/var/lib/apt/lists/archive.ubuntu.com*"
        "/etc/apt/apt.conf.d/99mirrors"
        "/etc/apt/apt.conf.d/99default-release"
    )
    
    for source in "${other_sources[@]}"; do
        if [ -e "$source" ]; then
            log_info "Removing: $source"
            rm -rf "$source" 2>/dev/null || true
        fi
    done
    
    # Check for any APT configuration files that might set mirrors
    if [ -d /etc/apt/apt.conf.d ]; then
        log_info "Checking APT configuration files..."
        for conf_file in /etc/apt/apt.conf.d/*; do
            if [ -f "$conf_file" ] && grep -q "Acquire::http::Proxy\|Acquire::https::Proxy\|APT::Get::AllowUnauthenticated" "$conf_file" 2>/dev/null; then
                log_info "Found APT config file: $conf_file"
                # Don't remove these, just log them
            fi
        done
    fi
    
    # Check if there are any sources in /usr/share/apt (common in some Docker images)
    if [ -d /usr/share/apt ]; then
        log_info "Checking /usr/share/apt for sources..."
        find /usr/share/apt -name "*.list" -o -name "sources*" -o -name "*.sources" 2>/dev/null | while read -r file; do
            if [ -f "$file" ]; then
                log_info "Found source in /usr/share/apt: $file"
                rm -f "$file" 2>/dev/null || true
            fi
        done
    fi
    
    log_success "APT sources cleaned"
}

# Function to update package lists
update_package_lists() {
    log_info "Updating package lists..."
    
    if apt-get update -y; then
        log_success "Package lists updated successfully"
    else
        log_error "Failed to update package lists"
        return 1
    fi
}

# Function to test mirror speed (optional)
test_mirror_speed() {
    # Check if speed testing is disabled
    if [ "${DISABLE_SPEED_TEST:-0}" -eq "1" ]; then
        log_info "Speed testing disabled by DISABLE_SPEED_TEST=1"
        return 0
    fi

    log_info "Testing mirror speed..."
    
    # This is a simple test - in production you might want more sophisticated testing
    local test_package="debian-archive-keyring"
    local start_time=$(date +%s)
    
    if apt-get download "$test_package" >/dev/null 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "Mirror test completed in ${duration}s"
        rm -f "${test_package}"*.deb 2>/dev/null || true
    else
        log_warning "Mirror speed test failed (this is normal for some mirrors)"
    fi
}

# Function to debug APT sources
debug_apt_sources() {
    log_info "Debugging APT sources configuration..."
    
    echo "=== Current sources.list content ===" >&2
    if [ -f /etc/apt/sources.list ]; then
        cat /etc/apt/sources.list >&2
    else
        echo "No sources.list file found" >&2
    fi
    
    echo "=== sources.list.d contents ===" >&2
    if [ -d /etc/apt/sources.list.d ]; then
        for file in /etc/apt/sources.list.d/*; do
            if [ -f "$file" ]; then
                echo "File: $file" >&2
                cat "$file" >&2
                echo "---" >&2
            fi
        done
    else
        echo "No sources.list.d directory found" >&2
    fi
    
    echo "=== APT configuration files ===" >&2
    if [ -d /etc/apt/apt.conf.d ]; then
        for file in /etc/apt/apt.conf.d/*; do
            if [ -f "$file" ]; then
                echo "Config file: $file" >&2
                cat "$file" >&2
                echo "---" >&2
            fi
        done
    fi
    
    echo "=== APT sources list (apt-cache policy) ===" >&2
    apt-cache policy 2>&1 | head -20 >&2
    
    echo "=== APT sources list (apt-get update debug) ===" >&2
    apt-get update -o Debug::Acquire::http=true 2>&1 | head -30 >&2
}

# Main function
main() {
    log_info "Starting mirror auto-selection..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Detect distribution
    detect_distro
    
    if [ "${DEBUG:-0}" -eq "1" ]; then
        # Debug current state
        log_info "=== DEBUG: Initial APT sources state ==="
        debug_apt_sources
    fi

    # Backup current sources
    backup_sources
    
    # Thoroughly clean APT sources
    clean_apt_sources
    
    # Detect location
    local country=$(detect_location)
    
    # Get appropriate mirrors
    local mirrors=$(get_mirrors "$country" "$DISTRO_NAME" "$DISTRO_CODENAME")
    
    # Write new sources.list
    log_info "Writing new sources.list..."
    echo "$mirrors" > /etc/apt/sources.list
    
    # Verify the file was written correctly
    if [ -f /etc/apt/sources.list ] && [ -s /etc/apt/sources.list ]; then
        log_success "Sources.list written successfully"
        log_info "Contents preview:"
        head -3 /etc/apt/sources.list | sed 's/^/  /' >&2
        
        # Verify no old mirrors are present
        if grep -q "deb.debian.org\|archive.ubuntu.com" /etc/apt/sources.list; then
            log_error "Old mirror references found in sources.list!"
            exit 1
        fi
    else
        log_error "Failed to write sources.list"
        exit 1
    fi
    
    if [ "${DEBUG:-0}" -eq "1" ]; then
        # Debug after configuration
        log_info "=== DEBUG: APT sources after configuration ==="
        debug_apt_sources
    fi
    
    # Update package lists
    if update_package_lists; then
        log_success "Mirror configuration completed successfully!"
        
        if [ "${DEBUG:-0}" -eq "1" ]; then
            # Verify only our mirrors are being used
            log_info "Verifying mirror configuration..."
            if apt-get update -o Debug::Acquire::http=true 2>&1 | grep -q "deb.debian.org\|archive.ubuntu.com"; then
                log_warning "Still detecting old mirrors - this might be from cached data"
                log_info "=== DEBUG: Final APT sources state ==="
                debug_apt_sources
            else
                log_success "Only configured mirrors are being used"
            fi
        fi

        # Optional: test mirror speed
        test_mirror_speed
        
        log_info "You can now use 'apt-get update' and 'apt-get install' with optimized mirrors"
    else
        log_error "Mirror configuration failed. Restoring backup..."
        
        # Restore main sources.list
        local backup_files=(/etc/apt/sources.list.backup.*)
        if [ ${#backup_files[@]} -gt 0 ]; then
            local latest_backup="${backup_files[-1]}"
            cp "$latest_backup" /etc/apt/sources.list
            log_warning "Restored main sources.list from $latest_backup"
        fi
        
        # Restore sources.list.d files
        local backup_dirs=(/etc/apt/sources.list.d.backup.*)
        if [ ${#backup_dirs[@]} -gt 0 ]; then
            local latest_backup_dir="${backup_dirs[-1]}"
            if [ -d "$latest_backup_dir" ]; then
                cp "$latest_backup_dir"/*.list /etc/apt/sources.list.d/ 2>/dev/null || true
                cp "$latest_backup_dir"/*.sources /etc/apt/sources.list.d/ 2>/dev/null || true
                log_warning "Restored sources.list.d files from $latest_backup_dir"
            fi
        fi
        
        log_warning "Backup restored. Please check your internet connection and try again."
        exit 1
    fi
}

# Run main function
main "$@"
