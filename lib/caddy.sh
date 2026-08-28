#!/usr/bin/env bash

CADDY_KEYRING="/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
CADDY_SOURCE="/etc/apt/sources.list.d/caddy-stable.list"
CADDY_GPG_URL="https://dl.cloudsmith.io/public/caddy/stable/gpg.key"
CADDY_REPO="https://dl.cloudsmith.io/public/caddy/stable/deb/debian"
CADDY_CONFIG="/etc/caddy/Caddyfile"

caddy_is_usable() {
    command -v caddy >/dev/null 2>&1 && caddy version >/dev/null 2>&1
}

caddy_service_active() {
    systemctl is-active --quiet caddy
}

port_listening() {
    local port="$1"
    ss -tln 2>/dev/null | awk '{print $4}' | grep -qE ":${port}\$"
}

setup_caddy_repo() {
    log INFO "Menyiapkan repository resmi Caddy (Cloudsmith)..."
    if [[ ! -f "$CADDY_KEYRING" ]]; then
        log INFO "Mengunduh kunci GPG resmi Caddy..."
        if ! curl -fsSL "$CADDY_GPG_URL" | gpg --dearmor -o "$CADDY_KEYRING" 2>/dev/null; then
            die "Gagal mengunduh kunci GPG Caddy dari $CADDY_GPG_URL"
        fi
        chmod a+r "$CADDY_KEYRING"
    fi
    if ! printf 'deb [signed-by=%s] %s any-version main\n' "$CADDY_KEYRING" "$CADDY_REPO" > "$CADDY_SOURCE" 2>/dev/null; then
        die "Gagal menulis konfigurasi repository Caddy di $CADDY_SOURCE"
    fi
    log OK "Repository resmi Caddy disiapkan"
}

install_caddy() {
    if caddy_is_usable; then
        log SKIP "Caddy sudah terpasang: $(caddy version)"
        return 0
    fi
    setup_caddy_repo
    log INFO "Menyegarkan apt setelah menambahkan repo Caddy..."
    if ! apt-get update -y >/dev/null 2>&1; then
        die "apt-get update gagal setelah menambahkan repo Caddy"
    fi
    log INFO "Menginstal Caddy (paket resmi)..."
    if ! apt-get install -y caddy >/dev/null 2>&1; then
        die "Gagal menginstal Caddy. Periksa dengan 'apt-get install -y caddy' manual"
    fi
    if ! caddy_is_usable; then
        die "Caddy tidak terdeteksi setelah instalasi"
    fi
    log OK "Caddy berhasil diinstal: $(caddy version)"
}

ensure_caddy_config() {
    if [[ -f "$CADDY_CONFIG" ]]; then
        log SKIP "Konfigurasi Caddy di $CADDY_CONFIG sudah ada, tidak ditimpa"
        return 0
    fi
    log INFO "Membuat konfigurasi Caddy minimal (foundation, tanpa project/domain)..."
    if ! printf ':80 {\n    respond "Caddy reverse proxy foundation ready. Domain dan route project akan dikonfigurasi pada milestone deployment."\n}\n' > "$CADDY_CONFIG" 2>/dev/null; then
        die "Gagal menulis konfigurasi Caddy di $CADDY_CONFIG"
    fi
    chmod 644 "$CADDY_CONFIG"
    log OK "Konfigurasi Caddy dibuat: $CADDY_CONFIG"
}

ensure_caddy_service() {
    if caddy_service_active; then
        log SKIP "Service caddy sudah aktif"
    else
        log INFO "Mengaktifkan dan memulai service caddy (systemctl enable --now caddy)..."
        if ! systemctl enable --now caddy >/dev/null 2>&1; then
            die "Gagal mengaktifkan service caddy. Periksa dengan 'systemctl enable --now caddy' manual"
        fi
        if ! caddy_service_active; then
            die "Service caddy tidak aktif setelah diaktifkan"
        fi
        log OK "Service caddy aktif"
    fi
    if systemctl is-enabled --quiet caddy 2>/dev/null; then
        log OK "caddy sudah enabled untuk boot"
    else
        log INFO "Mengaktifkan caddy untuk boot..."
        if ! systemctl enable caddy >/dev/null 2>&1; then
            log WARN "Gagal enable caddy untuk boot"
        else
            log OK "caddy enabled untuk boot"
        fi
    fi
}

validate_caddy() {
    if ! caddy_is_usable; then
        die "Caddy tidak terdeteksi"
    fi
    log OK "Caddy terdeteksi: $(caddy version) di $(command -v caddy)"
}

validate_caddy_config() {
    if [[ ! -f "$CADDY_CONFIG" ]]; then
        die "Konfigurasi Caddy $CADDY_CONFIG tidak ditemukan"
    fi
    if ! caddy validate --config "$CADDY_CONFIG" >/dev/null 2>&1; then
        die "caddy validate gagal pada $CADDY_CONFIG"
    fi
    log OK "caddy validate berhasil: $CADDY_CONFIG"
}

validate_caddy_ports() {
    log INFO "Memeriksa port 80/443 untuk Caddy..."
    if port_listening 80 || port_listening 443; then
        if caddy_service_active && port_listening 80; then
            log OK "Port 80/443 dikelola Caddy (service caddy aktif)"
            return 0
        fi
        log WARN "Port 80/443 sudah dipakai service lain. Caddy tetap terpasang/tervalidasi tetapi tidak memaksa mengambil alih port"
        return 0
    fi
    log OK "Port 80 dan 443 bebas — Caddy siap sebagai HTTPS foundation"
}

validate_caddy_service() {
    if ! caddy_service_active; then
        log WARN "Service caddy tidak aktif (config/ports memungkinkan tidak dijalankan)"
        return 0
    fi
    log OK "Service caddy aktif dan enabled"
}

run_p6() {
    log INFO "=== vps-setup | P6: Caddy Reverse Proxy + HTTPS Foundation ==="
    install_caddy
    ensure_caddy_config
    validate_caddy
    validate_caddy_config
    validate_caddy_ports
    ensure_caddy_service
    validate_caddy_service
    log INFO "P6: tidak ada project route, tidak ada domain, tidak ada sertifikat manual — HTTPS otomatis Caddy siap dikonfigurasi saat domain tersedia"
    log OK "P6 Caddy Reverse Proxy + HTTPS Foundation selesai"
}