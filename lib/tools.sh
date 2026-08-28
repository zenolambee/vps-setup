#!/usr/bin/env bash

# P7: Developer & AI CLI tools (OpenCode, npm, pnpm, GitHub CLI)
#
# Modul ini adalah pemilik tunggal fungsi install_pnpm dan install_gh —
# dipakai juga oleh run_p1 (lib/git.sh) dan run_p2 (lib/node.sh).
#
# Hanya memasang tooling global/system-level. Tidak clone repository project,
# tidak memasang dependency project, tidak menyentuh credential/authentication.

export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

# Node minimum yang masih kompatibel untuk tooling P7.
# Versi yang lebih baru dipertahankan, tidak pernah di-downgrade oleh P7.
TOOLS_NODE_MIN_MAJOR=20

# GitHub CLI — repository resmi
GH_APT_KEYRING="/usr/share/keyrings/githubcli-archive-keyring.gpg"
GH_APT_SOURCE="/etc/apt/sources.list.d/github-cli.list"
GH_REPO_URL="https://cli.github.com/packages"

# OpenCode — paket resmi npm (metode instalasi resmi, global/system-level)
OPENCODE_NPM_PKG="opencode-ai"

opencode_is_usable() {
    command -v opencode >/dev/null 2>&1 && opencode --version >/dev/null 2>&1
}

opencode_version() {
    opencode --version 2>/dev/null | awk 'NR==1'
}

# --- npm & Node (tidak pernah downgrade Node yang sudah ada) ---

install_node_tools() {
    local major
    if ! node_is_usable; then
        die "Node.js tidak terdeteksi. Jalankan P2 lebih dulu — P7 tidak memasang atau mengganti Node.js"
    fi
    major="$(node_major)"
    if [[ -z "$major" || "$major" -lt "$TOOLS_NODE_MIN_MAJOR" ]]; then
        die "Node.js aktif $(node --version) (major ${major:-?}) < $TOOLS_NODE_MIN_MAJOR — tidak kompatibel. Jalankan P2; P7 tidak mengganti Node.js"
    fi
    if [[ "$major" -gt "$TOOLS_NODE_MIN_MAJOR" ]]; then
        log SKIP "Node.js $(node --version) (major $major) lebih baru dari minimum $TOOLS_NODE_MIN_MAJOR — dipertahankan, tidak di-downgrade"
    else
        log SKIP "Node.js $(node --version) sesuai minimum $TOOLS_NODE_MIN_MAJOR — dipertahankan"
    fi

    if npm_is_usable; then
        log SKIP "npm sudah tersedia: $(npm --version)"
    else
        log INFO "Menginstal npm (bundled dengan Node.js)..."
        if ! apt-get install -y npm >/dev/null 2>&1 || ! npm_is_usable; then
            die "Gagal menyediakan npm. Periksa dengan 'apt-get install -y npm' manual"
        fi
        log OK "npm tersedia: $(npm --version)"
    fi

    if corepack_is_usable; then
        log SKIP "Corepack sudah tersedia: $(corepack --version)"
    else
        die "Corepack tidak tersedia. Corepack dibundel dengan Node.js — periksa instalasi Node.js (P2)"
    fi
}

# --- pnpm via Corepack (pemilik tunggal; dipakai run_p2 dan run_p7) ---

install_pnpm() {
    if ! corepack_is_usable; then
        die "Corepack tidak tersedia. Corepack dibundel dengan Node.js — periksa instalasi Node.js"
    fi
    if pnpm_is_usable; then
        log SKIP "pnpm sudah tersedia via Corepack: $(pnpm --version) ($(command -v pnpm))"
        return 0
    fi
    log INFO "Mengaktifkan shim pnpm via Corepack (corepack enable pnpm)..."
    if ! corepack enable pnpm 2>/dev/null; then
        die "Gagal mengaktifkan shim pnpm (corepack enable pnpm)"
    fi
    if pnpm_is_usable; then
        log OK "pnpm tersedia via Corepack: $(pnpm --version) ($(command -v pnpm))"
    else
        log WARN "Shim pnpm belum aktif di shell ini. Jalankan 'corepack enable pnpm' atau buka shell baru"
    fi
}

# --- GitHub CLI (pemilik tunggal; dipakai run_p1 dan run_p7) ---

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
        log SKIP "GitHub CLI sudah tersedia dan valid: $(gh --version | head -1) ($(command -v gh)) — instalasi existing dipakai, tidak reinstall"
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

# --- OpenCode ---

install_opencode() {
    if opencode_is_usable; then
        log SKIP "OpenCode sudah terpasang: $(opencode_version) ($(command -v opencode)) — instalasi existing dipakai, tidak reinstall"
        return 0
    fi
    if ! npm_is_usable; then
        die "npm tidak tersedia — dibutuhkan untuk memasang OpenCode dari paket resmi npm"
    fi
    log INFO "Menginstal OpenCode global dari paket resmi npm ($OPENCODE_NPM_PKG)..."
    if ! npm install -g "$OPENCODE_NPM_PKG" >/dev/null 2>&1; then
        die "Gagal menginstal OpenCode. Periksa dengan 'npm install -g $OPENCODE_NPM_PKG' manual"
    fi
    if ! opencode_is_usable; then
        die "OpenCode tidak terdeteksi setelah instalasi. Pastikan direktori bin npm global ada di PATH"
    fi
    log OK "OpenCode berhasil diinstal: $(opencode_version)"
}

# --- Validasi ---

# Node divalidasi dengan semantik minimum (>=), bukan pinning ke satu major
# seperti validate_node di P2 — P7 tidak boleh menolak versi yang lebih baru.
validate_tools_node() {
    local major
    if ! node_is_usable; then
        die "Node.js tidak terdeteksi"
    fi
    major="$(node_major)"
    if [[ -z "$major" || "$major" -lt "$TOOLS_NODE_MIN_MAJOR" ]]; then
        die "Node.js aktif $(node --version) (major ${major:-?}) < minimum $TOOLS_NODE_MIN_MAJOR"
    fi
    log OK "Node.js terdeteksi: $(node --version) (major $major >= $TOOLS_NODE_MIN_MAJOR) ($(command -v node))"
}

validate_opencode() {
    if ! opencode_is_usable; then
        die "OpenCode tidak terdeteksi atau 'opencode --version' gagal"
    fi
    log OK "OpenCode terdeteksi: $(opencode_version) ($(command -v opencode))"
}

# OpenCode tidak boleh diautentikasi atau dikonfigurasi otomatis oleh installer
validate_opencode_no_credentials() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
    if [[ -e "$cfg" ]]; then
        log SKIP "Konfigurasi OpenCode milik pengguna sudah ada di $cfg — tidak dibaca, tidak diubah, tidak dibuat ulang"
    else
        log OK "Tidak ada $cfg — installer tidak membuat config atau credential OpenCode"
    fi
    log INFO "P7 tidak menjalankan login/authentication OpenCode dan tidak menulis API key ke mana pun"
}

# gh: status authentication tidak diubah, token tidak pernah dibaca/dicetak
validate_gh_auth_untouched() {
    if gh auth status >/dev/null 2>&1; then
        log SKIP "GitHub CLI sudah authenticated — status dipertahankan, tidak logout, token tidak dibaca/dicetak"
    else
        log OK "GitHub CLI belum authenticated — installer tidak menjalankan 'gh auth login' dan tidak meminta token"
    fi
}

validate_tools() {
    log INFO "Memvalidasi developer & AI CLI tools..."
    validate_tools_node
    validate_npm
    validate_corepack
    validate_pnpm
    validate_gh
    validate_gh_auth_untouched
    validate_opencode
    validate_opencode_no_credentials
    log OK "Semua tool P7 tervalidasi: node, npm, corepack, pnpm, gh, opencode"
}

run_p7() {
    log INFO "=== vps-setup | P7: Developer & AI CLI Tools ==="
    install_node_tools
    install_pnpm
    install_gh
    install_opencode
    validate_tools
    log INFO "P7 hanya memasang tooling global: tanpa clone repository project, tanpa dependency project, tanpa credential/token"
    log OK "P7 Developer & AI CLI Tools selesai"
}
