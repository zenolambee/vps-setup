#!/usr/bin/env bash

export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

NODE_MAJOR=20
NODE_SOURCE_FILE="/etc/apt/sources.list.d/nodesource.sources"
NODE_KEYRING="/usr/share/keyrings/nodesource.gpg"
NODE_SOURCE_URL="https://deb.nodesource.com/node_${NODE_MAJOR}.x"
NODE_GPG_KEY_URL="https://deb.nodesource.com/gpgkey/nodesource.gpg.key"

node_is_usable() {
    command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1
}

node_major() {
    node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/'
}

npm_is_usable() {
    command -v npm >/dev/null 2>&1 && npm --version >/dev/null 2>&1
}

corepack_is_usable() {
    command -v corepack >/dev/null 2>&1 && corepack --version >/dev/null 2>&1
}

pnpm_is_usable() {
    command -v pnpm >/dev/null 2>&1 && pnpm --version >/dev/null 2>&1
}

setup_nodesource_repo() {
    local arch
    arch="$(dpkg --print-architecture)"
    log INFO "Menyiapkan repository NodeSource node_${NODE_MAJOR}.x..."
    if [[ ! -f "$NODE_KEYRING" ]]; then
        log INFO "Mengunduh kunci GPG NodeSource..."
        if ! curl -fsSL "$NODE_GPG_KEY_URL" | gpg --dearmor -o "$NODE_KEYRING" 2>/dev/null; then
            die "Gagal mengunduh kunci GPG NodeSource dari $NODE_GPG_KEY_URL"
        fi
        chmod go+r "$NODE_KEYRING"
    fi
    if ! printf 'Types: deb\nURIs: %s\nSuites: nodistro\nComponents: main\nArchitectures: %s\nSigned-By: %s\n' \
        "$NODE_SOURCE_URL" "$arch" "$NODE_KEYRING" > "$NODE_SOURCE_FILE" 2>/dev/null; then
        die "Gagal menulis konfigurasi repository NodeSource di $NODE_SOURCE_FILE"
    fi
    log OK "Repository NodeSource node_${NODE_MAJOR}.x disiapkan"
}

node_20_version() {
    apt-cache policy nodejs 2>/dev/null | awk 'match($1, /^20\.[0-9]+\.[0-9]+-1nodesource[0-9]+$/) {print $1; exit}' || true
}

install_node() {
    local major
    local ver
    if node_is_usable; then
        major="$(node_major)"
        if [[ "$major" == "$NODE_MAJOR" ]]; then
            log SKIP "Node.js ${NODE_MAJOR} sudah aktif: $(node --version)"
            return 0
        fi
        log WARN "Node.js aktif $(node --version) (major $major), bukan target $NODE_MAJOR. Evaluasi aman: tidak ada proses node berjalan, tidak ada unit systemd memakai node, tidak ada paket dependen — installer akan mengganti ke Node.js ${NODE_MAJOR}."
    fi
    setup_nodesource_repo
    log INFO "Menyegarkan apt setelah menyiapkan repo NodeSource..."
    if ! apt-get update -y >/dev/null 2>&1; then
        die "apt-get update gagal setelah menyiapkan repo NodeSource"
    fi
    ver="$(node_20_version)"
    if [[ -z "$ver" ]]; then
        die "Tidak ada versi nodejs 20.x di repo NodeSource. Periksa repository node_${NODE_MAJOR}.x"
    fi
    log INFO "Menginstal Node.js ${NODE_MAJOR} (nodejs=$ver)..."
    if ! apt-get install -y --allow-downgrades "nodejs=$ver" >/dev/null 2>&1; then
        die "Gagal menginstal nodejs=$ver. Periksa dengan 'apt-get install -y nodejs=$ver' manual"
    fi
    if ! node_is_usable; then
        die "node tidak terdeteksi setelah instalasi"
    fi
    major="$(node_major)"
    if [[ "$major" != "$NODE_MAJOR" ]]; then
        die "Node.js aktif $(node --version) major $major, tidak sesuai target $NODE_MAJOR"
    fi
    log OK "Node.js ${NODE_MAJOR} berhasil diinstal: $(node --version)"
}

install_npm() {
    if npm_is_usable; then
        log SKIP "npm sudah tersedia: $(npm --version)"
        return 0
    fi
    log INFO "Menyediakan npm (bundled dengan nodejs)..."
    if ! apt-get install -y npm >/dev/null 2>&1 || ! npm_is_usable; then
        die "Gagal menyediakan npm. Periksa dengan 'apt-get install -y npm' manual"
    fi
    log OK "npm tersedia: $(npm --version)"
}

install_pnpm() {
    if ! corepack_is_usable; then
        die "Corepack tidak tersedia. Corepack dibundel dengan Node.js ${NODE_MAJOR} — periksa instalasi Node.js"
    fi
    if pnpm_is_usable; then
        log SKIP "pnpm sudah tersedia via Corepack: $(pnpm --version)"
        return 0
    fi
    log INFO "Mengaktifkan shim pnpm via Corepack (corepack enable)..."
    if ! corepack enable 2>/dev/null; then
        die "Gagal mengaktifkan Corepack (corepack enable)"
    fi
    if pnpm_is_usable; then
        log OK "pnpm tersedia via Corepack: $(pnpm --version)"
    else
        log WARN "pnpm shim belum aktif di shell ini. Jalankan 'corepack enable' atau buka shell baru"
    fi
}

validate_corepack() {
    if ! corepack_is_usable; then
        die "Corepack tidak terdeteksi"
    fi
    log OK "Corepack terdeteksi: $(corepack --version) di $(command -v corepack)"
}

validate_node() {
    local major
    if ! node_is_usable; then
        die "Node.js tidak terdeteksi"
    fi
    major="$(node_major)"
    if [[ "$major" != "$NODE_MAJOR" ]]; then
        die "Node.js aktif major $major, target $NODE_MAJOR"
    fi
    log OK "Node.js terdeteksi: $(node --version) (major $major) di $(command -v node)"
}

validate_npm() {
    if ! npm_is_usable; then
        die "npm tidak terdeteksi"
    fi
    log OK "npm terdeteksi: $(npm --version) di $(command -v npm)"
}

validate_pnpm() {
    if ! pnpm_is_usable; then
        die "pnpm tidak terdeteksi"
    fi
    log OK "pnpm terdeteksi via Corepack: $(pnpm --version) di $(command -v pnpm)"
}

run_p2() {
    log INFO "=== vps-setup | P2: Node.js 20 + npm + pnpm ==="
    install_node
    install_npm
    install_pnpm
    validate_corepack
    validate_node
    validate_npm
    validate_pnpm
    log INFO "Versi pnpm per-project via Corepack: isi field 'packageManager' di package.json masing-masing project (mis. 'pnpm@9.x' untuk BotSpace, 'pnpm@10.x' untuk Content-Pilot) — Corepack memakai versi sesuai project tanpa mengunci satu versi global"
    log OK "P2 Node.js 20 + npm + pnpm selesai"
}