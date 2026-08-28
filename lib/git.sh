#!/usr/bin/env bash

GH_APT_KEYRING="/usr/share/keyrings/githubcli-archive-keyring.gpg"
GH_APT_SOURCE="/etc/apt/sources.list.d/github-cli.list"
GH_REPO_URL="https://cli.github.com/packages"

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

setup_gh_repo() {
    local arch
    arch="$(dpkg --print-architecture)"
    log INFO "Menambahkan repository resmi GitHub CLI..."
    mkdir -p "$(dirname "$GH_APT_KEYRING")"
    if ! curl -fsSL "$GH_REPO_URL/githubcli-archive-keyring.gpg" -o "$GH_APT_KEYRING" 2>/dev/null; then
        die "Gagal mengunduh kunci GPG GitHub CLI dari $GH_REPO_URL"
    fi
    chmod go+r "$GH_APT_KEYRING"
    if ! echo "deb [arch=$arch signed-by=$GH_APT_KEYRING] $GH_REPO_URL stable main" > "$GH_APT_SOURCE" 2>/dev/null; then
        die "Gagal menulis konfigurasi repository GitHub CLI di $GH_APT_SOURCE"
    fi
    log OK "Repository resmi GitHub CLI ditambahkan"
}

install_gh() {
    if gh_is_usable; then
        log SKIP "GitHub CLI sudah tersedia: $(gh --version | head -1)"
        return 0
    fi
    setup_gh_repo
    log INFO "Menyegarkan apt setelah menambahkan repo GitHub CLI..."
    if ! apt-get update -y >/dev/null 2>&1; then
        die "apt-get update gagal setelah menambahkan repo GitHub CLI"
    fi
    log INFO "Menginstal GitHub CLI..."
    if apt-get install -y gh >/dev/null 2>&1 && gh_is_usable; then
        log OK "GitHub CLI berhasil diinstal: $(gh --version | head -1)"
    else
        die "Gagal menginstal GitHub CLI. Periksa dengan 'apt-get install -y gh' manual"
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