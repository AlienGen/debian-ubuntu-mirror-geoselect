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
# - HTTP transport fallbacks: curl, wget, openssl, bash /dev/tcp
# - Offline heuristics from timezone and locale when network geo fails
# - Ordered mirror candidates with apt-get update verification
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
#   - bash
#   - Internet connectivity (for geolocation and apt)
#   - Root privileges (for writing to /etc/apt/sources.list)
#   - Optional: curl or wget (openssl or /dev/tcp used as fallbacks)
#
# Environment:
#   FORCE_COUNTRY=XX       Bypass geolocation (ISO country code)
#   DISABLE_SPEED_TEST=1   Skip apt-get download speed test
#   DEBUG=1                Verbose APT sources debugging
#
# Author: AlienGen Team
# License: MIT License
# Version: 1.1.0
# Last Updated: 2026
#
# =============================================================================

set -e

if [ -z "$DEBUG" ]; then
    DEBUG=0
fi

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

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

# Normalize and validate a 2-letter country code (first non-empty line)
normalize_country() {
    local raw
    raw=$(printf '%s\n' "$1" | tr -d '\r' | sed '/^$/d' | head -1 | tr -d '\t ' | tr '[:lower:]' '[:upper:]')
    if [[ "$raw" =~ ^[A-Z]{2}$ ]]; then
        echo "$raw"
        return 0
    fi
    return 1
}

# Parse URL into scheme, host, path (path includes leading /)
parse_url() {
    local url="$1"
    local rest host path

    case "$url" in
        https://*)
            HTTP_SCHEME="https"
            rest="${url#https://}"
            ;;
        http://*)
            HTTP_SCHEME="http"
            rest="${url#http://}"
            ;;
        *)
            return 1
            ;;
    esac

    host="${rest%%/*}"
    if [ "$host" = "$rest" ]; then
        path="/"
    else
        path="/${rest#*/}"
    fi

    HTTP_HOST="$host"
    HTTP_PATH="$path"
}

# Extract HTTP response body (headers end at first blank line)
http_extract_body() {
    awk '
        BEGIN { body = 0 }
        body { print; next }
        /^\r?$/ { body = 1 }
    '
}

# GET via openssl s_client (HTTPS)
http_get_openssl() {
    local host="$1"
    local path="$2"
    local response body

    if ! command -v openssl >/dev/null 2>&1; then
        return 1
    fi

    response=$(
        printf 'GET %s HTTP/1.0\r\nHost: %s\r\nUser-Agent: mirror-geoselect/1.1\r\nConnection: close\r\n\r\n' \
            "$path" "$host" |
            openssl s_client -quiet -connect "${host}:443" -servername "$host" 2>/dev/null
    ) || return 1

    body=$(printf '%s\n' "$response" | http_extract_body | tr -d '\r')
    [ -n "$body" ] || return 1
    printf '%s\n' "$body"
}

# GET via bash /dev/tcp (HTTP only)
http_get_devtcp() {
    local host="$1"
    local path="$2"
    local response body

    response=$(
        {
            exec 3<>"/dev/tcp/${host}/80" || exit 1
            printf 'GET %s HTTP/1.0\r\nHost: %s\r\nUser-Agent: mirror-geoselect/1.1\r\nConnection: close\r\n\r\n' \
                "$path" "$host" >&3
            cat <&3
            exec 3<&-
            exec 3>&-
        } 2>/dev/null
    ) || return 1

    body=$(printf '%s\n' "$response" | http_extract_body | tr -d '\r')
    [ -n "$body" ] || return 1
    printf '%s\n' "$body"
}

# HTTP GET with transport cascade: curl → wget → openssl → /dev/tcp
# Sets HTTP_TRANSPORT to the transport that succeeded.
http_get() {
    local url="$1"
    local body=""

    HTTP_TRANSPORT=""

    if command -v curl >/dev/null 2>&1; then
        if body=$(curl -fsSL --max-time 10 --retry 2 "$url" 2>/dev/null); then
            if [ -n "$body" ]; then
                HTTP_TRANSPORT="curl"
                printf '%s\n' "$body"
                return 0
            fi
        fi
    fi

    if command -v wget >/dev/null 2>&1; then
        if body=$(wget -qO- --timeout=10 "$url" 2>/dev/null); then
            if [ -n "$body" ]; then
                HTTP_TRANSPORT="wget"
                printf '%s\n' "$body"
                return 0
            fi
        fi
    fi

    if ! parse_url "$url"; then
        return 1
    fi

    if [ "$HTTP_SCHEME" = "https" ]; then
        if body=$(http_get_openssl "$HTTP_HOST" "$HTTP_PATH"); then
            HTTP_TRANSPORT="openssl"
            printf '%s\n' "$body"
            return 0
        fi
    elif [ "$HTTP_SCHEME" = "http" ]; then
        if body=$(http_get_devtcp "$HTTP_HOST" "$HTTP_PATH"); then
            HTTP_TRANSPORT="devtcp"
            printf '%s\n' "$body"
            return 0
        fi
    fi

    return 1
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        DISTRO_NAME="$ID"
        DISTRO_VERSION="$VERSION_ID"
        DISTRO_CODENAME="$VERSION_CODENAME"
    elif [ -f /etc/debian_version ]; then
        DISTRO_NAME="debian"
        DISTRO_VERSION=$(cat /etc/debian_version)
        case "$DISTRO_VERSION" in
            "12"*) DISTRO_CODENAME="bookworm" ;;
            "11"*) DISTRO_CODENAME="bullseye" ;;
            "10"*) DISTRO_CODENAME="buster" ;;
            *) DISTRO_CODENAME="bookworm" ;;
        esac
    else
        log_error "Unable to detect distribution"
        exit 1
    fi

    log_info "Detected: $DISTRO_NAME $DISTRO_VERSION ($DISTRO_CODENAME)"
}

# Infer country from timezone / locale when network geo is unavailable
infer_location_from_system() {
    local tz="" locale_val="" country=""

    if [ -n "${TZ:-}" ]; then
        tz="$TZ"
    elif [ -f /etc/timezone ]; then
        tz=$(tr -d '\r\n' </etc/timezone)
    elif [ -L /etc/localtime ]; then
        tz=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
    fi

    if [ -n "$tz" ]; then
        case "$tz" in
            Asia/Shanghai*|Asia/Chongqing*|Asia/Harbin*|Asia/Urumqi*|Asia/Kashgar*|PRC)
                country="CN" ;;
            Asia/Hong_Kong*) country="HK" ;;
            Asia/Taipei*) country="TW" ;;
            Asia/Macau*|Asia/Macao*) country="MO" ;;
            Asia/Tokyo*|Japan) country="JP" ;;
            Asia/Seoul*|ROK) country="KR" ;;
            Asia/Singapore*|Singapore) country="SG" ;;
            Asia/Kuala_Lumpur*|Asia/Kuching*) country="MY" ;;
            Asia/Bangkok*) country="TH" ;;
            Asia/Ho_Chi_Minh*|Asia/Saigon*) country="VN" ;;
            Asia/Jakarta*|Asia/Pontianak*|Asia/Makassar*|Asia/Jayapura*) country="ID" ;;
            Asia/Manila*) country="PH" ;;
            Australia/*|NZ*|Pacific/Auckland*|Pacific/Chatham*)
                case "$tz" in
                    NZ*|Pacific/Auckland*|Pacific/Chatham*) country="NZ" ;;
                    *) country="AU" ;;
                esac
                ;;
            Europe/London*|Europe/Belfast*|GB*|Europe/Isle_of_Man*|Europe/Jersey*|Europe/Guernsey*)
                country="GB" ;;
            Europe/Dublin*|Eire) country="IE" ;;
            Europe/Berlin*|Europe/Vienna*|Europe/Zurich*|Europe/Amsterdam*|Europe/Brussels*|\
            Europe/Paris*|Europe/Rome*|Europe/Madrid*|Europe/Lisbon*|Europe/Andorra*|\
            Europe/Luxembourg*|Europe/Monaco*|Europe/Malta*|Europe/Vatican*|\
            Atlantic/Canary*|Atlantic/Madeira*|Arctic/Longyearbyen*)
                case "$tz" in
                    Europe/Berlin*|Europe/Busingen*) country="DE" ;;
                    Europe/Vienna*) country="AT" ;;
                    Europe/Zurich*) country="CH" ;;
                    Europe/Amsterdam*) country="NL" ;;
                    Europe/Brussels*) country="BE" ;;
                    Europe/Paris*|Europe/Monaco*) country="FR" ;;
                    Europe/Rome*|Europe/Vatican*|Europe/Malta*|Europe/San_Marino*) country="IT" ;;
                    Europe/Madrid*|Atlantic/Canary*|Africa/Ceuta*) country="ES" ;;
                    Europe/Lisbon*|Atlantic/Madeira*|Atlantic/Azores*) country="PT" ;;
                    *) country="DE" ;;
                esac
                ;;
            America/New_York*|America/Chicago*|America/Denver*|America/Los_Angeles*|\
            America/Phoenix*|America/Anchorage*|America/Honolulu*|US/*|Pacific/Honolulu*)
                country="US" ;;
        esac

        if [ -n "$country" ]; then
            log_info "Inferred location from timezone ($tz): $country"
            echo "$country"
            return 0
        fi
    fi

    for locale_val in "${LC_ALL:-}" "${LC_CTYPE:-}" "${LANG:-}"; do
        [ -n "$locale_val" ] || continue
        case "$locale_val" in
            C|C.*|POSIX) continue ;;
        esac
        if country=$(echo "$locale_val" | sed -n 's/^.*_\([A-Za-z][A-Za-z]\).*/\1/p' | tr '[:lower:]' '[:upper:]'); then
            if country=$(normalize_country "$country"); then
                log_info "Inferred location from locale ($locale_val): $country"
                echo "$country"
                return 0
            fi
        fi
    done

    return 1
}

detect_location() {
    if [ -n "${FORCE_COUNTRY:-}" ]; then
        local forced
        if forced=$(normalize_country "$FORCE_COUNTRY"); then
            log_info "Forcing country $forced"
            echo "$forced"
            return
        fi
        log_warning "Invalid FORCE_COUNTRY='$FORCE_COUNTRY', ignoring"
    fi

    log_info "Detecting geographical location..."

    local country="" body=""
    local services=(
        "https://ipapi.co/country_code"
        "https://ipinfo.io/country"
        "https://ifconfig.me/country-iso"
        "http://ip-api.com/line/?fields=countryCode"
    )

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        if command -v openssl >/dev/null 2>&1; then
            log_info "curl/wget not available; using openssl for HTTPS geolocation"
        else
            log_warning "curl/wget/openssl not available; will try HTTP /dev/tcp and offline heuristics"
        fi
    fi

    for service in "${services[@]}"; do
        log_info "Trying service: $service"
        if body=$(http_get "$service" 2>/dev/null); then
            if country=$(normalize_country "$body"); then
                log_success "Location detected: $country (via $HTTP_TRANSPORT)"
                echo "$country"
                return
            fi
        fi
    done

    log_warning "Network geolocation failed, trying offline heuristics..."
    if country=$(infer_location_from_system); then
        log_success "Location inferred: $country"
        echo "$country"
        return
    fi

    log_warning "Geolocation detection failed, using default (US)"
    echo "US"
}

# Build Debian sources.list content for an archive + security base URL
build_debian_sources() {
    local archive_url="$1"
    local security_url="$2"
    local codename="$3"
    cat << EOF
deb ${archive_url} ${codename} main contrib non-free non-free-firmware
deb ${archive_url} ${codename}-updates main contrib non-free non-free-firmware
deb ${archive_url} ${codename}-backports main contrib non-free non-free-firmware
deb ${security_url} ${codename}-security main contrib non-free non-free-firmware
EOF
}

build_ubuntu_sources() {
    local archive_url="$1"
    local codename="$2"
    cat << EOF
deb ${archive_url} ${codename} main restricted universe multiverse
deb ${archive_url} ${codename}-updates main restricted universe multiverse
deb ${archive_url} ${codename}-backports main restricted universe multiverse
deb ${archive_url} ${codename}-security main restricted universe multiverse
EOF
}

# Populate global array MIRROR_CANDIDATES with ordered sources.list bodies
# (primary regional → alternate → official CDN)
get_mirror_candidates() {
    local country="$1"
    local distro="$2"
    local codename="$3"
    local debian_security="https://security.debian.org/debian-security"

    MIRROR_CANDIDATES=()
    MIRROR_CANDIDATE_LABELS=()

    log_info "Selecting mirrors for $country..."

    add_debian_candidate() {
        local label="$1"
        local archive="$2"
        local security="${3:-$debian_security}"
        MIRROR_CANDIDATE_LABELS+=("$label")
        MIRROR_CANDIDATES+=("$(build_debian_sources "$archive" "$security" "$codename")")
    }

    add_ubuntu_candidate() {
        local label="$1"
        local archive="$2"
        MIRROR_CANDIDATE_LABELS+=("$label")
        MIRROR_CANDIDATES+=("$(build_ubuntu_sources "$archive" "$codename")")
    }

    case "$country" in
        CN|HK|TW|MO)
            log_info "Using Chinese mirrors (regional → CDN fallback)"
            if [ "$distro" = "debian" ]; then
                add_debian_candidate "Tsinghua" "https://mirrors.tuna.tsinghua.edu.cn/debian/" \
                    "https://mirrors.tuna.tsinghua.edu.cn/debian-security"
                add_debian_candidate "USTC" "https://mirrors.ustc.edu.cn/debian/" \
                    "https://mirrors.ustc.edu.cn/debian-security"
                add_debian_candidate "Debian CDN" "https://deb.debian.org/debian/"
            elif [ "$distro" = "ubuntu" ]; then
                add_ubuntu_candidate "Tsinghua" "https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
                add_ubuntu_candidate "USTC" "https://mirrors.ustc.edu.cn/ubuntu/"
                add_ubuntu_candidate "Ubuntu archive" "https://archive.ubuntu.com/ubuntu/"
            fi
            ;;
        JP|KR)
            log_info "Using Japanese mirrors (regional → CDN fallback)"
            if [ "$distro" = "debian" ]; then
                add_debian_candidate "ftp.jp.debian.org" "https://ftp.jp.debian.org/debian/"
                add_debian_candidate "Debian CDN" "https://deb.debian.org/debian/"
            elif [ "$distro" = "ubuntu" ]; then
                add_ubuntu_candidate "jp.archive.ubuntu.com" "https://jp.archive.ubuntu.com/ubuntu/"
                add_ubuntu_candidate "Ubuntu archive" "https://archive.ubuntu.com/ubuntu/"
            fi
            ;;
        SG|MY|TH|VN|ID|PH)
            log_info "Using Singapore mirrors (regional → CDN fallback)"
            if [ "$distro" = "debian" ]; then
                add_debian_candidate "ftp.sg.debian.org" "https://ftp.sg.debian.org/debian/"
                add_debian_candidate "Debian CDN" "https://deb.debian.org/debian/"
            elif [ "$distro" = "ubuntu" ]; then
                add_ubuntu_candidate "sg.archive.ubuntu.com" "https://sg.archive.ubuntu.com/ubuntu/"
                add_ubuntu_candidate "Ubuntu archive" "https://archive.ubuntu.com/ubuntu/"
            fi
            ;;
        AU|NZ)
            log_info "Using Australian mirrors (regional → CDN fallback)"
            if [ "$distro" = "debian" ]; then
                add_debian_candidate "ftp.au.debian.org" "https://ftp.au.debian.org/debian/"
                add_debian_candidate "Debian CDN" "https://deb.debian.org/debian/"
            elif [ "$distro" = "ubuntu" ]; then
                add_ubuntu_candidate "au.archive.ubuntu.com" "https://au.archive.ubuntu.com/ubuntu/"
                add_ubuntu_candidate "Ubuntu archive" "https://archive.ubuntu.com/ubuntu/"
            fi
            ;;
        GB|IE)
            log_info "Using UK mirrors (regional → CDN fallback)"
            if [ "$distro" = "debian" ]; then
                add_debian_candidate "ftp.uk.debian.org" "https://ftp.uk.debian.org/debian/"
                add_debian_candidate "Debian CDN" "https://deb.debian.org/debian/"
            elif [ "$distro" = "ubuntu" ]; then
                add_ubuntu_candidate "gb.archive.ubuntu.com" "https://gb.archive.ubuntu.com/ubuntu/"
                add_ubuntu_candidate "Ubuntu archive" "https://archive.ubuntu.com/ubuntu/"
            fi
            ;;
        DE|AT|CH|NL|BE|FR|IT|ES|PT)
            log_info "Using European mirrors (CDN)"
            if [ "$distro" = "debian" ]; then
                add_debian_candidate "Debian CDN" "https://deb.debian.org/debian/"
            elif [ "$distro" = "ubuntu" ]; then
                add_ubuntu_candidate "Ubuntu archive" "https://archive.ubuntu.com/ubuntu/"
            fi
            ;;
        *)
            log_info "Using US / default mirrors (CDN)"
            if [ "$distro" = "debian" ]; then
                add_debian_candidate "Debian CDN" "https://deb.debian.org/debian/"
            elif [ "$distro" = "ubuntu" ]; then
                add_ubuntu_candidate "us.archive.ubuntu.com" "https://us.archive.ubuntu.com/ubuntu/"
                add_ubuntu_candidate "Ubuntu archive" "https://archive.ubuntu.com/ubuntu/"
            fi
            ;;
    esac

    if [ ${#MIRROR_CANDIDATES[@]} -eq 0 ]; then
        log_error "No mirror candidates for distro='$distro' country='$country'"
        return 1
    fi
}

backup_sources() {
    local backup_file="/etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S)"
    local sources_backup_dir="/etc/apt/sources.list.d.backup.$(date +%Y%m%d_%H%M%S)"

    mkdir -p "$sources_backup_dir"

    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list "$backup_file"
        log_success "Backup created: $backup_file"
    else
        log_warning "No existing /etc/apt/sources.list found - this is normal in some Docker images"
        touch "$backup_file"
    fi

    if [ -d /etc/apt/sources.list.d ]; then
        local file_count=0
        for file in /etc/apt/sources.list.d/*.list; do
            if [ -f "$file" ]; then
                cp "$file" "$sources_backup_dir/"
                file_count=$((file_count + 1))
            fi
        done

        if [ "$file_count" -gt 0 ]; then
            log_success "Backed up $file_count files from sources.list.d to $sources_backup_dir"
        else
            log_info "No .list files found in sources.list.d"
        fi
    else
        log_info "No sources.list.d directory found"
    fi

    if [ ! -f /etc/apt/sources.list ] && [ ! -d /etc/apt/sources.list.d ]; then
        log_warning "No APT sources found - this might be a minimal Docker image"
    fi
}

find_all_apt_sources() {
    log_info "Searching for all APT sources locations..."

    local found_sources=()
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

    log_info "Searching for files containing mirror references..."
    local mirror_files
    mirror_files=$(find /etc -name "*.list" -o -name "*.conf" -o -name "sources*" -o -name "*.sources" 2>/dev/null | grep -E "(apt|sources)" || true)

    for file in $mirror_files; do
        if [ -f "$file" ] && grep -q "deb\.debian\.org\|archive\.ubuntu.com" "$file" 2>/dev/null; then
            log_info "Found mirror reference in: $file"
            found_sources+=("$file")
        fi
    done

    if [ -n "${APT_SOURCES:-}" ]; then
        log_info "Found APT_SOURCES environment variable"
        found_sources+=("APT_SOURCES_ENV")
    fi

    echo "${found_sources[@]}"
}

clean_apt_sources() {
    log_info "Thoroughly cleaning APT sources..."

    # Intentionally capture for side-effect logging
    find_all_apt_sources >/dev/null

    apt-get clean 2>/dev/null || true
    rm -rf /var/lib/apt/lists/* 2>/dev/null || true

    if [ -d /etc/apt/sources.list.d ]; then
        log_info "Removing all sources.list.d files..."
        rm -f /etc/apt/sources.list.d/*.list 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/*.save 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/*.conf 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/*.sources 2>/dev/null || true
    fi

    if [ -f /etc/apt/sources.list ]; then
        log_info "Clearing existing sources.list..."
        rm -f /etc/apt/sources.list
    fi

    rm -f /etc/apt/sources.list.save 2>/dev/null || true
    rm -rf /etc/apt/sources.list.d.save 2>/dev/null || true

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

    if [ -d /etc/apt/apt.conf.d ]; then
        log_info "Checking APT configuration files..."
        for conf_file in /etc/apt/apt.conf.d/*; do
            if [ -f "$conf_file" ] && grep -q "Acquire::http::Proxy\|Acquire::https::Proxy\|APT::Get::AllowUnauthenticated" "$conf_file" 2>/dev/null; then
                log_info "Found APT config file: $conf_file"
            fi
        done
    fi

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

update_package_lists() {
    log_info "Updating package lists..."

    if apt-get update -y; then
        log_success "Package lists updated successfully"
        return 0
    fi

    log_error "Failed to update package lists"
    return 1
}

write_sources_list() {
    local mirrors="$1"
    local label="$2"

    log_info "Writing sources.list (candidate: $label)..."
    printf '%s\n' "$mirrors" > /etc/apt/sources.list

    if [ ! -f /etc/apt/sources.list ] || [ ! -s /etc/apt/sources.list ]; then
        log_error "Failed to write sources.list"
        return 1
    fi

    if ! grep -qE '^deb ' /etc/apt/sources.list; then
        log_error "sources.list has no deb entries"
        return 1
    fi

    log_success "Sources.list written successfully"
    log_info "Contents preview:"
    head -3 /etc/apt/sources.list | sed 's/^/  /' >&2
    return 0
}

# Try each mirror candidate until apt-get update succeeds
apply_mirrors_with_fallback() {
    local i
    for i in "${!MIRROR_CANDIDATES[@]}"; do
        local label="${MIRROR_CANDIDATE_LABELS[$i]}"
        local mirrors="${MIRROR_CANDIDATES[$i]}"

        if ! write_sources_list "$mirrors" "$label"; then
            continue
        fi

        if update_package_lists; then
            SELECTED_MIRROR_LABEL="$label"
            return 0
        fi

        log_warning "Candidate '$label' failed apt-get update, trying next fallback..."
    done

    return 1
}

restore_backups() {
    log_error "Mirror configuration failed. Restoring backup..."

    local backup_files=(/etc/apt/sources.list.backup.*)
    if [ ${#backup_files[@]} -gt 0 ] && [ -e "${backup_files[0]}" ]; then
        local latest_backup="${backup_files[-1]}"
        cp "$latest_backup" /etc/apt/sources.list
        log_warning "Restored main sources.list from $latest_backup"
    fi

    local backup_dirs=(/etc/apt/sources.list.d.backup.*)
    if [ ${#backup_dirs[@]} -gt 0 ] && [ -e "${backup_dirs[0]}" ]; then
        local latest_backup_dir="${backup_dirs[-1]}"
        if [ -d "$latest_backup_dir" ]; then
            cp "$latest_backup_dir"/*.list /etc/apt/sources.list.d/ 2>/dev/null || true
            cp "$latest_backup_dir"/*.sources /etc/apt/sources.list.d/ 2>/dev/null || true
            log_warning "Restored sources.list.d files from $latest_backup_dir"
        fi
    fi

    log_warning "Backup restored. Please check your internet connection and try again."
}

test_mirror_speed() {
    if [ "${DISABLE_SPEED_TEST:-0}" = "1" ]; then
        log_info "Speed testing disabled by DISABLE_SPEED_TEST=1"
        return 0
    fi

    log_info "Testing mirror speed..."

    local test_package="debian-archive-keyring"
    local start_time end_time duration
    start_time=$(date +%s)

    if apt-get download "$test_package" >/dev/null 2>&1; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_success "Mirror test completed in ${duration}s"
        rm -f "${test_package}"*.deb 2>/dev/null || true
    else
        log_warning "Mirror speed test failed (this is normal for some mirrors)"
    fi
}

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

main() {
    log_info "Starting mirror auto-selection..."

    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    detect_distro

    if [ "${DEBUG:-0}" = "1" ]; then
        log_info "=== DEBUG: Initial APT sources state ==="
        debug_apt_sources
    fi

    backup_sources
    clean_apt_sources

    local country
    country=$(detect_location)

    get_mirror_candidates "$country" "$DISTRO_NAME" "$DISTRO_CODENAME"

    if [ "${DEBUG:-0}" = "1" ]; then
        log_info "=== DEBUG: Mirror candidates ==="
        local i
        for i in "${!MIRROR_CANDIDATE_LABELS[@]}"; do
            log_info "  [$i] ${MIRROR_CANDIDATE_LABELS[$i]}"
        done
    fi

    if apply_mirrors_with_fallback; then
        log_success "Mirror configuration completed successfully! (using $SELECTED_MIRROR_LABEL)"

        if [ "${DEBUG:-0}" = "1" ]; then
            log_info "=== DEBUG: APT sources after configuration ==="
            debug_apt_sources
        fi

        test_mirror_speed
        log_info "You can now use 'apt-get update' and 'apt-get install' with optimized mirrors"
    else
        restore_backups
        exit 1
    fi
}

main "$@"
