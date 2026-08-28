#!/usr/bin/env bash

set -Eeuo pipefail

LOG_DIR="/var/log/vps-setup"
LOG_FILE="$LOG_DIR/setup.log"
export DEBIAN_FRONTEND=noninteractive

setup_logging() {
    if mkdir -p "$LOG_DIR" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null; then
        return 0
    fi
    LOG_DIR="${TMPDIR:-/tmp}/vps-setup"
    LOG_FILE="$LOG_DIR/setup.log"
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    log WARN "Tidak dapat menulis ke /var/log/vps-setup, log dialihkan ke $LOG_FILE"
}

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "$timestamp [$level] $message" | tee -a "$LOG_FILE"
}

die() {
    log ERROR "$1"
    exit "${2:-1}"
}

err_handler() {
    local line="$1"
    log ERROR "Terjadi error pada baris $line (file: ${BASH_SOURCE[1]##*/}, fungsi: ${FUNCNAME[1]:-main})"
    exit 1
}

trap 'err_handler $LINENO' ERR
