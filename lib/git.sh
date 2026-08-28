#!/usr/bin/env bash

# GitHub CLI (install_gh, setup_gh_repo) didefinisikan di lib/tools.sh (P7)
# sebagai pemilik tunggal, dipakai bersama oleh run_p1 dan run_p7.

git_is_usable() {
    command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1
}

gh_is_usable() {
    command -v gh >/dev/null 2>&1 && gh --version >/dev/null 2>&1
}

check_git_config() {
    local name email
    name="$(git config --global user.name 2>/dev/null || true)"
    email="$(git config --global user.email 2>/dev/null || true)"
    if [[ -n "$name" || -n "$email" ]]; then
        log OK "Konfigurasi Git global sudah ada, tidak diubah oleh installer"
    else
        log WARN "user.name/user.email global belum diset. Installer tidak mengubahnya — set manual sesuai kebutuhan"
    fi
}

install_git() {
    if git_is_usable; then
        log SKIP "Git sudah tersedia: $(git --version)"
        return 0
    fi
    log INFO "Menginstal Git..."
    if apt-get install -y git >/dev/null 2>&1 && git_is_usable; then
        log OK "Git berhasil diinstal: $(git --version)"
    else
        die "Gagal menginstal Git. Periksa dengan 'apt-get install -y git' manual"
    fi
}

validate_git() {
    if ! git_is_usable; then
        die "Git tidak terdeteksi setelah instalasi"
    fi
    log OK "Git terdeteksi: $(git --version) ($(command -v git))"
    check_git_config
}

validate_gh() {
    if ! gh_is_usable; then
        die "GitHub CLI tidak terdeteksi setelah instalasi"
    fi
    log OK "GitHub CLI terdeteksi: $(gh --version | head -1) ($(command -v gh))"
}

run_p1() {
    log INFO "=== vps-setup | P1: Git + GitHub CLI ==="
    install_git
    install_gh
    validate_git
    validate_gh
    log OK "P1 Git + GitHub CLI selesai"
}
