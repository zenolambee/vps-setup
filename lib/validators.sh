#!/usr/bin/env bash

check_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        log OK "Menjalankan sebagai root"
    elif sudo -n true 2>/dev/null; then
        log OK "Akses sudo tersedia"
    else
        die "Harus dijalankan sebagai root atau dengan akses sudo"
    fi
}

check_os() {
    local id
    if [[ ! -f /etc/os-release ]]; then
        die "Tidak dapat mendeteksi sistem operasi (/etc/os-release tidak ditemukan)"
    fi
    . /etc/os-release
    id="${ID:-}"
    case "$id" in
        ubuntu|debian)
            log OK "Sistem operasi didukung: ${PRETTY_NAME:-$id} ${VERSION_ID:-}"
            ;;
        *)
            die "Sistem operasi '$id' tidak didukung. P0 hanya mendukung Ubuntu/Debian"
            ;;
    esac
}

check_arch() {
    local arch
    arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    case "$arch" in
        amd64|arm64)
            log OK "Arsitektur didukung: $arch"
            ;;
        *)
            die "Arsitektur '$arch' tidak didukung (hanya amd64/arm64)"
            ;;
    esac
}

check_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        log OK "Package manager tersedia: apt-get"
    else
        die "apt-get tidak ditemukan di sistem ini"
    fi
}

check_apt_process() {
    local proc
    local lock
    for proc in apt-get apt dpkg; do
        if pgrep -x "$proc" >/dev/null 2>&1; then
            die "Proses '$proc' masih berjalan. Tunggu hingga selesai, lalu jalankan ulang installer"
        fi
    done
    if command -v fuser >/dev/null 2>&1; then
        for lock in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock; do
            if [[ -e "$lock" ]] && fuser "$lock" >/dev/null 2>&1; then
                die "Lock $lock sedang dipegang proses lain. Tunggu hingga selesai, lalu jalankan ulang installer"
            fi
        done
    fi
    log OK "Tidak ada proses apt/dpkg lain yang berjalan"
}

check_pkg_repo() {
    log INFO "Menguji koneksi ke repository package manager..."
    if ! apt-get update -y >/dev/null 2>&1; then
        die "apt-get update gagal. Periksa koneksi jaringan dan konfigurasi repository"
    fi
    log OK "Koneksi repository package manager berhasil"
}

check_disk_space() {
    local needed_kb=524288
    local available
    available="$(df -Pk / | awk 'NR==2 {print $4}')"
    if [[ -n "$available" && "$available" -lt "$needed_kb" ]]; then
        die "Ruang disk tidak cukup: tersedia ${available} KB, minimal dibutuhkan $((needed_kb / 1024)) MB"
    fi
    log OK "Ruang disk mencukupi"
}