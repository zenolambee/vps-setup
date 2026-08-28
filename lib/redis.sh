#!/usr/bin/env bash

REDIS_PORT=6379

redis_is_usable() {
    command -v redis-server >/dev/null 2>&1 && command -v redis-cli >/dev/null 2>&1
}

redis_service_active() {
    systemctl is-active --quiet redis-server
}

install_redis() {
    if redis_is_usable; then
        log SKIP "Redis sudah tersedia: $(redis-server --version)"
        return 0
    fi
    log INFO "Menginstal Redis (paket resmi Ubuntu/Debian)..."
    if ! apt-get install -y redis-server >/dev/null 2>&1; then
        die "Gagal menginstal Redis. Periksa dengan 'apt-get install -y redis-server' manual"
    fi
    if ! redis_is_usable; then
        die "Redis tidak terdeteksi setelah instalasi"
    fi
    log OK "Redis berhasil diinstal: $(redis-server --version)"
}

ensure_redis_service() {
    if redis_service_active; then
        log SKIP "Service redis-server sudah aktif"
        return 0
    fi
    log INFO "Mengaktifkan dan memulai service redis-server (systemctl enable --now redis-server)..."
    if ! systemctl enable --now redis-server >/dev/null 2>&1; then
        die "Gagal mengaktifkan service redis-server"
    fi
    if ! redis_service_active; then
        die "Service redis-server tidak aktif setelah diaktifkan"
    fi
    log OK "Service redis-server aktif"
}

validate_redis() {
    local ver pong
    if ! redis_is_usable; then
        die "Redis tidak terdeteksi"
    fi
    ver="$(redis-server --version 2>&1)"
    pong="$(redis-cli -h 127.0.0.1 -p "$REDIS_PORT" ping 2>&1 || true)"
    log OK "Redis terdeteksi: $ver"
    if [[ "$pong" != "PONG" ]]; then
        die "redis-cli ping gagal di port $REDIS_PORT (jawaban: ${pong:-kosong})"
    fi
    log OK "Redis merespons health check lokal (redis-cli ping -> PONG)"
}

run_p5_redis() {
    log INFO "--- Redis ---"
    install_redis
    ensure_redis_service
    validate_redis
}