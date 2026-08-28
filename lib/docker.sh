#!/usr/bin/env bash

DOCKER_KEYRING="/etc/apt/keyrings/docker.asc"
DOCKER_SOURCE="/etc/apt/sources.list.d/docker.list"
DOCKER_GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
DOCKER_REPO="https://download.docker.com/linux"
DOCKER_TEST_IMAGE="hello-world:latest"

docker_is_usable() {
    command -v docker >/dev/null 2>&1 && docker --version >/dev/null 2>&1
}

compose_is_usable() {
    docker compose version >/dev/null 2>&1
}

docker_service_active() {
    systemctl is-active --quiet docker
}

docker_ce_installed() {
    dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q 'install ok installed'
}

setup_docker_repo() {
    local os_id codename arch
    . /etc/os-release
    os_id="${ID:-ubuntu}"
    codename="${VERSION_CODENAME:-noble}"
    arch="$(dpkg --print-architecture)"
    log INFO "Menyiapkan repository resmi Docker ($os_id/$codename)..."
    mkdir -p /etc/apt/keyrings
    if [[ ! -f "$DOCKER_KEYRING" ]]; then
        log INFO "Mengunduh kunci GPG resmi Docker..."
        if ! curl -fsSL "$DOCKER_GPG_URL" -o "$DOCKER_KEYRING" 2>/dev/null; then
            die "Gagal mengunduh kunci GPG Docker dari $DOCKER_GPG_URL"
        fi
        chmod a+r "$DOCKER_KEYRING"
    fi
    if ! printf 'deb [arch=%s signed-by=%s] %s/%s %s stable\n' "$arch" "$DOCKER_KEYRING" "$DOCKER_REPO" "$os_id" "$codename" > "$DOCKER_SOURCE" 2>/dev/null; then
        die "Gagal menulis konfigurasi repository Docker di $DOCKER_SOURCE"
    fi
    log OK "Repository resmi Docker disiapkan"
}

install_docker() {
    if docker_is_usable && docker_ce_installed; then
        log SKIP "Docker Engine sudah terpasang dari sumber resmi: $(docker --version)"
        return 0
    fi
    setup_docker_repo
    log INFO "Menyegarkan apt setelah menambahkan repo Docker..."
    if ! apt-get update -y >/dev/null 2>&1; then
        die "apt-get update gagal setelah menambahkan repo Docker"
    fi
    log INFO "Menginstal docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin..."
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1; then
        die "Gagal menginstal Docker. Periksa dengan 'apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin' manual"
    fi
    if ! docker_is_usable; then
        die "docker tidak terdeteksi setelah instalasi"
    fi
    log OK "Docker Engine berhasil diinstal: $(docker --version)"
}

install_compose() {
    if compose_is_usable; then
        log SKIP "Docker Compose v2 sudah tersedia: $(docker compose version)"
        return 0
    fi
    if ! docker_is_usable; then
        install_docker
    fi
    log INFO "Menginstal docker-compose-plugin (Docker Compose v2)..."
    if ! apt-get install -y docker-compose-plugin >/dev/null 2>&1 || ! compose_is_usable; then
        die "Gagal menginstal docker-compose-plugin. Periksa dengan 'apt-get install -y docker-compose-plugin' manual"
    fi
    log OK "Docker Compose v2 terinstal: $(docker compose version)"
}

ensure_docker_service() {
    if docker_service_active; then
        log SKIP "Service docker sudah aktif"
        return 0
    fi
    log INFO "Mengaktifkan dan memulai service docker (systemctl enable --now docker)..."
    if ! systemctl enable --now docker >/dev/null 2>&1; then
        die "Gagal mengaktifkan service docker. Periksa dengan 'systemctl enable --now docker' manual"
    fi
    if ! docker_service_active; then
        die "Service docker tidak aktif setelah diaktifkan"
    fi
    log OK "Service docker aktif"
}

ensure_docker_group() {
    local dev_users u
    if ! getent group docker >/dev/null 2>&1; then
        log INFO "Membuat group docker..."
        if ! groupadd docker 2>/dev/null; then
            die "Gagal membuat group docker"
        fi
    fi
    dev_users="$(awk -F: '$3>=1000 && $3<65534 {print $1}' /etc/passwd 2>/dev/null || true)"
    if [[ -z "$dev_users" ]]; then
        log INFO "Tidak ada user non-root development terdeteksi — akses docker untuk root sudah tersedia tanpa konfigurasi tambahan"
        return 0
    fi
    for u in $dev_users; do
        if id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
            log SKIP "User '$u' sudah anggota group docker"
        else
            log INFO "Menambahkan user '$u' ke group docker..."
            if usermod -aG docker "$u" 2>/dev/null; then
                log WARN "User '$u' ditambahkan ke group docker — session baru diperlukan agar berlaku, tidak ada logout paksa/restart VPS"
            else
                log WARN "Gagal menambahkan user '$u' ke group docker (dilewati)"
            fi
        fi
    done
}

validate_docker() {
    if ! docker_is_usable; then
        die "docker tidak terdeteksi"
    fi
    log OK "Docker terdeteksi: $(docker --version) di $(command -v docker)"
}

validate_docker_service() {
    if ! docker_service_active; then
        die "Service docker tidak aktif"
    fi
    if ! docker info >/dev/null 2>&1; then
        die "Daemon Docker tidak dapat diakses (docker info gagal)"
    fi
    log OK "Service docker aktif dan daemon dapat diakses"
}

validate_compose() {
    local ver
    ver="$(docker compose version 2>&1 || true)"
    if [[ -z "$ver" ]]; then
        die "Docker Compose v2 (plugin) tidak terdeteksi"
    fi
    log OK "Docker Compose v2 terdeteksi: $ver"
}

compose_config_check() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    printf 'services:\n  test:\n    image: %s\n' "$DOCKER_TEST_IMAGE" > "$tmpdir/docker-compose.yml"
    if docker compose -f "$tmpdir/docker-compose.yml" config >/dev/null 2>&1; then
        log OK "Validasi konfigurasi compose sederhana berhasil (tanpa menjalankan project)"
    else
        log WARN "Validasi konfigurasi compose gagal pada file test — plugin tetap terdeteksi"
    fi
    rm -rf "$tmpdir"
}

test_docker_isolated() {
    local pulled=0
    log INFO "Menguji Docker dengan container ringan resmi ($DOCKER_TEST_IMAGE)..."
    if ! docker image inspect "$DOCKER_TEST_IMAGE" >/dev/null 2>&1; then
        if ! docker pull "$DOCKER_TEST_IMAGE" >/dev/null 2>&1; then
            log WARN "Tidak dapat pull image $DOCKER_TEST_IMAGE (jaringan/rate-limit) — daemon tetap sehat, test container dilewati"
            return 0
        fi
        pulled=1
    fi
    if ! docker run --rm --name "vps-setup-p4-test" "$DOCKER_TEST_IMAGE" >/dev/null 2>&1; then
        log WARN "Gagal menjalankan container test — daemon tetap sehat, test dilewati"
    else
        log OK "Container test $DOCKER_TEST_IMAGE berhasil dijalankan dan dibersihkan (--rm)"
    fi
    docker rm -f "vps-setup-p4-test" >/dev/null 2>&1 || true
    if [[ "$pulled" -eq 1 ]]; then
        docker image rm "$DOCKER_TEST_IMAGE" >/dev/null 2>&1 || true
        log INFO "Image test $DOCKER_TEST_IMAGE dihapus — resource test dibersihkan"
    fi
}

run_p4() {
    log INFO "=== vps-setup | P4: Docker + Docker Compose ==="
    install_docker
    install_compose
    ensure_docker_service
    ensure_docker_group
    validate_docker
    validate_docker_service
    validate_compose
    compose_config_check
    test_docker_isolated
    log INFO "Keamanan P4: tidak ada expose API TCP, tidak ada port daemon, tidak ada remote API, tidak ada insecure config, tidak ada perubahan firewall"
    log OK "P4 Docker + Docker Compose selesai"
}