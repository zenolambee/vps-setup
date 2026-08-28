#!/usr/bin/env bash

CADDY_KEYRING="/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
CADDY_SOURCE="/etc/apt/sources.list.d/caddy-stable.list"
CADDY_GPG_URL="https://dl.cloudsmith.io/public/caddy/stable/gpg.key"
CADDY_REPO="https://dl.cloudsmith.io/public/caddy/stable/deb/debian"
CADDY_CONFIG="${CADDY_CONFIG:-/etc/caddy/Caddyfile}"
CADDY_CONF_DIR="${CADDY_CONF_DIR:-/etc/caddy/conf.d}"
CADDY_DATA_DIR="/var/lib/caddy"
CADDY_HTTP_PORTS=(80 443)
CADDY_ADMIN_PORT=2019
# Port backend yang harus tetap privat (P5 + Docker API) — hanya diperiksa, tidak diubah
CADDY_PRIVATE_PORTS=(5432 6379 9000 9001 2375 2376)

caddy_version_line() {
    caddy version 2>/dev/null | awk 'NR==1'
}

caddy_is_usable() {
    command -v caddy >/dev/null 2>&1 && caddy version >/dev/null 2>&1
}

caddy_pkg_installed() {
    dpkg-query -W -f='${Status}' caddy 2>/dev/null | grep -q 'install ok installed'
}

caddy_service_exists() {
    systemctl cat caddy.service >/dev/null 2>&1
}

caddy_service_active() {
    systemctl is-active --quiet caddy 2>/dev/null
}

# --- Port inspection helpers (read-only, tidak pernah menghentikan apa pun) ---

# Baris listener ss untuk sebuah port (tanpa header)
caddy_port_listeners() {
    local port="$1"
    ss -H -tlnp 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {print}'
}

caddy_port_listening() {
    local port="$1"
    [[ -n "$(caddy_port_listeners "$port")" ]]
}

# Nama process pemilik port (mis. caddy, nginx, docker-proxy)
caddy_port_owner_process() {
    local port="$1"
    caddy_port_listeners "$port" |
        grep -oE '"[^"]+"' |
        tr -d '"' |
        sort -u |
        paste -sd, - 2>/dev/null || true
}

# Alamat bind port (mis. *:80, 127.0.0.1:5432)
caddy_port_bindings() {
    local port="$1"
    caddy_port_listeners "$port" | awk '{print $4}' | sort -u | paste -sd', ' - 2>/dev/null || true
}

# Container Docker yang mempublikasikan port tersebut (jika Docker tersedia)
caddy_port_owner_container() {
    local port="$1"
    command -v docker >/dev/null 2>&1 || return 0
    docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null |
        awk -v p=":$port->" '$0 ~ p {print $1}' |
        paste -sd, - 2>/dev/null || true
}

caddy_port_bound_publicly() {
    local port="$1"
    caddy_port_listeners "$port" | awk '{print $4}' |
        grep -qvE '^(127\.0\.0\.1|\[::1\]|localhost)'
}

caddy_owns_port() {
    local port="$1"
    caddy_port_owner_process "$port" | grep -qw 'caddy'
}

# Port 80/443 bebas, atau memang milik Caddy → aman mengaktifkan service
caddy_ports_safe() {
    local port
    for port in "${CADDY_HTTP_PORTS[@]}"; do
        if caddy_port_listening "$port" && ! caddy_owns_port "$port"; then
            return 1
        fi
    done
    return 0
}

# --- Instalasi ---

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
        if caddy_pkg_installed; then
            log SKIP "Caddy sudah terpasang dari paket resmi: $(caddy_version_line) — tidak reinstall"
        else
            log SKIP "Caddy sudah terpasang dan valid: $(caddy_version_line) — instalasi existing dipakai, tidak reinstall"
        fi
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
    log OK "Caddy berhasil diinstal: $(caddy_version_line)"
}

# --- Konfigurasi foundation (tanpa domain, tanpa route project) ---

caddy_write_foundation_config() {
    local target="$1"
    cat > "$target" <<CADDYFILE
# Caddy foundation — vps-setup P6
#
# Tanpa domain project, tanpa reverse proxy project, tanpa sertifikat manual.
# Site block per-domain ditambahkan nanti sebagai file terpisah di
# $CADDY_CONF_DIR, sehingga file ini tidak perlu diubah lagi. Saat site block
# berdomain ditambahkan, Caddy menerbitkan sertifikat ACME dan mengaktifkan
# HTTPS + redirect HTTP->HTTPS secara otomatis.
{
	# Admin API dibatasi ke localhost — tidak terekspos ke jaringan.
	admin localhost:$CADDY_ADMIN_PORT
}

# Konfigurasi per-domain (kosong pada P6).
import $CADDY_CONF_DIR/*.caddy

:80 {
	respond /healthz "ok" 200
	respond "vps-setup: Caddy foundation aktif. Belum ada domain atau route project." 200
}
CADDYFILE
}

ensure_caddy_config() {
    if [[ ! -d "$CADDY_CONF_DIR" ]]; then
        log INFO "Membuat direktori konfigurasi per-domain $CADDY_CONF_DIR ..."
        mkdir -p "$CADDY_CONF_DIR"
        chmod 755 "$CADDY_CONF_DIR"
        log OK "Direktori $CADDY_CONF_DIR dibuat (kosong, siap untuk konfigurasi domain pada milestone deployment)"
    else
        log SKIP "Direktori $CADDY_CONF_DIR sudah ada — isinya tidak dibaca ulang, tidak diubah, tidak dihapus"
    fi

    if [[ -f "$CADDY_CONFIG" ]]; then
        log SKIP "Konfigurasi Caddy $CADDY_CONFIG sudah ada — dipertahankan apa adanya, tidak ditimpa, tanpa duplikasi"
        return 0
    fi

    log INFO "Membuat konfigurasi Caddy foundation (tanpa domain, tanpa route project)..."
    if ! caddy_write_foundation_config "$CADDY_CONFIG" 2>/dev/null; then
        die "Gagal menulis konfigurasi Caddy di $CADDY_CONFIG"
    fi
    chmod 644 "$CADDY_CONFIG"
    log OK "Konfigurasi Caddy foundation dibuat: $CADDY_CONFIG"
}

# --- Service ---

ensure_caddy_service() {
    if ! caddy_service_exists; then
        die "Unit systemd caddy.service tidak tersedia setelah instalasi"
    fi
    log OK "Unit systemd caddy.service tersedia"

    if caddy_service_active; then
        log SKIP "Service caddy sudah aktif dan sehat — tidak direstart, tidak di-reload"
    elif ! caddy_ports_safe; then
        log WARN "Service caddy tidak diaktifkan: port 80/443 dipegang process lain. Port tidak diambil alih, process/container tidak dihentikan"
        return 0
    else
        log INFO "Mengaktifkan service caddy (systemctl enable --now caddy)..."
        if ! systemctl enable --now caddy >/dev/null 2>&1; then
            die "Gagal mengaktifkan service caddy. Periksa 'systemctl status caddy' dan 'journalctl -u caddy'"
        fi
        if ! caddy_service_active; then
            die "Service caddy tidak aktif setelah diaktifkan"
        fi
        log OK "Service caddy aktif"
    fi

    if systemctl is-enabled --quiet caddy 2>/dev/null; then
        log SKIP "caddy sudah enabled untuk boot"
    else
        log INFO "Mengaktifkan caddy untuk boot..."
        if systemctl enable caddy >/dev/null 2>&1; then
            log OK "caddy enabled untuk boot"
        else
            log WARN "Gagal enable caddy untuk boot — perlu pemeriksaan manual"
        fi
    fi
}

# --- Validasi ---

validate_caddy() {
    if ! caddy_is_usable; then
        die "Caddy tidak terdeteksi atau 'caddy version' gagal"
    fi
    log OK "caddy version: $(caddy_version_line) ($(command -v caddy))"
}

validate_caddy_config() {
    local extra
    if [[ ! -f "$CADDY_CONFIG" ]]; then
        die "Konfigurasi Caddy $CADDY_CONFIG tidak ditemukan"
    fi
    if ! caddy validate --config "$CADDY_CONFIG" >/dev/null 2>&1; then
        die "caddy validate gagal pada $CADDY_CONFIG — konfigurasi tidak diubah, resolusi manual diperlukan"
    fi
    log OK "caddy validate: $CADDY_CONFIG valid"
    extra="$(find "$CADDY_CONF_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
    log OK "Konfigurasi per-domain di $CADDY_CONF_DIR: ${extra} file (dipertahankan apa adanya)"
    log INFO "P6 tidak membuat domain project, route BotSpace/Content-Pilot/Toko Online/MT-Info, perubahan DNS, atau sertifikat manual"
}

validate_caddy_ports() {
    local port owner container
    log INFO "Memeriksa port 80/443..."
    for port in "${CADDY_HTTP_PORTS[@]}"; do
        if ! caddy_port_listening "$port"; then
            log OK "Port $port bebas — tersedia untuk Caddy"
            continue
        fi
        owner="$(caddy_port_owner_process "$port")"
        container="$(caddy_port_owner_container "$port")"
        if caddy_owns_port "$port"; then
            log OK "Port $port dikelola Caddy (process: ${owner:-caddy}; bind: $(caddy_port_bindings "$port"))"
        else
            log WARN "Port $port dipakai process lain: ${owner:-tidak diketahui}${container:+ (container: $container)}; bind: $(caddy_port_bindings "$port")"
            log WARN "Port $port TIDAK diambil alih dan process/container TIDAK dihentikan — binary serta konfigurasi Caddy tetap divalidasi"
        fi
    done
}

validate_caddy_service() {
    local main_pid
    if ! caddy_service_exists; then
        die "Unit systemd caddy.service tidak ditemukan"
    fi
    if ! caddy_service_active; then
        log WARN "Service caddy tidak aktif (kemungkinan port 80/443 dipakai service lain) — binary dan konfigurasi tetap valid"
        return 0
    fi
    log OK "systemd: caddy active, boot state: $(systemctl is-enabled caddy 2>/dev/null || echo 'tidak diketahui')"
    main_pid="$(systemctl show caddy -p MainPID --value 2>/dev/null || true)"
    if [[ -n "$main_pid" && "$main_pid" != "0" ]]; then
        log OK "Proses caddy berjalan (MainPID $main_pid, user: $(systemctl show caddy -p User --value 2>/dev/null || echo caddy))"
    fi
}

# Admin API Caddy tidak boleh terekspos ke interface publik
validate_caddy_admin_security() {
    if systemctl is-active --quiet caddy-api 2>/dev/null; then
        log WARN "Service caddy-api aktif (admin API sebagai config source) — tidak diubah oleh P6, tinjau kebutuhannya"
    else
        log OK "Service caddy-api tidak aktif — admin API tidak dijadikan config source"
    fi
    if ! caddy_port_listening "$CADDY_ADMIN_PORT"; then
        log OK "Admin API Caddy (port $CADDY_ADMIN_PORT) tidak listening — tidak terekspos"
        return 0
    fi
    if caddy_port_bound_publicly "$CADDY_ADMIN_PORT"; then
        log WARN "Admin API Caddy ter-bind non-lokal ($(caddy_port_bindings "$CADDY_ADMIN_PORT")) — sebaiknya dibatasi ke localhost. Konfigurasi pengguna tidak diubah otomatis"
    else
        log OK "Admin API Caddy hanya lokal ($(caddy_port_bindings "$CADDY_ADMIN_PORT")) — tidak terekspos ke publik"
    fi
}

# Verifikasi P6 tidak mengekspos backend P4/P5 (PostgreSQL, Redis, MinIO, Docker API)
validate_caddy_backend_isolation() {
    local port label
    log INFO "Memeriksa isolasi backend (P6 tidak boleh mengekspos service internal)..."
    for port in "${CADDY_PRIVATE_PORTS[@]}"; do
        case "$port" in
            5432) label="PostgreSQL" ;;
            6379) label="Redis" ;;
            9000) label="MinIO API" ;;
            9001) label="MinIO Console" ;;
            2375|2376) label="Docker API" ;;
            *) label="backend" ;;
        esac
        if ! caddy_port_listening "$port"; then
            log OK "Port $port ($label) tidak listening — tidak terekspos oleh P6"
        elif caddy_port_bound_publicly "$port"; then
            log WARN "Port $port ($label) ter-bind non-lokal ($(caddy_port_bindings "$port")) — bukan perubahan P6, sebaiknya dibatasi ke 127.0.0.1"
        else
            log OK "Port $port ($label) tetap lokal ($(caddy_port_bindings "$port"))"
        fi
    done
    log OK "P6 tidak membuat reverse proxy ke backend mana pun — PostgreSQL, Redis, MinIO, dan Docker API tetap privat"
}

# Fondasi HTTPS otomatis: storage sertifikat siap, tanpa domain/DNS/sertifikat manual
validate_caddy_https_foundation() {
    local svc_user cert_root
    svc_user="$(systemctl show caddy -p User --value 2>/dev/null || true)"
    svc_user="${svc_user:-caddy}"
    if [[ ! -d "$CADDY_DATA_DIR" ]]; then
        log WARN "Direktori data Caddy $CADDY_DATA_DIR belum ada — dibuat otomatis oleh service saat sertifikat pertama diterbitkan"
    else
        log OK "Direktori data Caddy siap: $CADDY_DATA_DIR (service user: $svc_user, owner: $(stat -c '%U:%G' "$CADDY_DATA_DIR" 2>/dev/null || echo 'tidak diketahui'))"
    fi
    cert_root="$CADDY_DATA_DIR/.local/share/caddy"
    if [[ -d "$cert_root" ]]; then
        log OK "Storage sertifikat ACME tersedia: $cert_root"
    else
        log OK "Storage sertifikat ACME akan dibuat di $cert_root saat domain pertama dikonfigurasi"
    fi
    if grep -qE '^[[:space:]]*auto_https[[:space:]]+off' "$CADDY_CONFIG" 2>/dev/null; then
        log WARN "Konfigurasi memuat 'auto_https off' — HTTPS otomatis nonaktif (konfigurasi pengguna, tidak diubah oleh P6)"
    else
        log OK "HTTPS otomatis aktif secara default — sertifikat ACME diterbitkan saat site block berdomain ditambahkan ke $CADDY_CONF_DIR"
    fi
    log INFO "Fondasi HTTPS siap: port 443 dan redirect HTTP->HTTPS ditangani Caddy otomatis tanpa konfigurasi domain di P6"
}

# Tes HTTP lokal hanya jika Caddy memang memegang port 80
validate_caddy_local_http() {
    local code
    if ! caddy_service_active; then
        log SKIP "Tes HTTP lokal dilewati: service caddy tidak aktif"
        return 0
    fi
    if ! caddy_owns_port 80; then
        log SKIP "Tes HTTP lokal dilewati: port 80 tidak dikelola Caddy"
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1; then
        log SKIP "Tes HTTP lokal dilewati: curl tidak tersedia"
        return 0
    fi
    code="$(curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1/ 2>/dev/null || true)"
    if [[ -n "$code" && "$code" != "000" ]]; then
        log OK "HTTP lokal dilayani Caddy (127.0.0.1:80 -> HTTP $code)"
    else
        log WARN "HTTP lokal pada 127.0.0.1:80 tidak merespons — periksa 'journalctl -u caddy'"
    fi
}

run_p6() {
    log INFO "=== vps-setup | P6: Caddy Reverse Proxy + HTTPS Foundation ==="
    validate_caddy_ports
    install_caddy
    ensure_caddy_config
    validate_caddy
    validate_caddy_config
    ensure_caddy_service
    validate_caddy_service
    validate_caddy_ports
    validate_caddy_admin_security
    validate_caddy_backend_isolation
    validate_caddy_https_foundation
    validate_caddy_local_http
    log INFO "P6 hanya menyediakan foundation: tanpa domain project, tanpa route project, tanpa perubahan DNS, tanpa sertifikat manual"
    log OK "P6 Caddy Reverse Proxy + HTTPS Foundation selesai"
}
