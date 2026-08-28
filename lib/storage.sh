#!/usr/bin/env bash

STORAGE_PORTS=(5432 6379 9000 9001)

port_in_use() {
    local port="$1"
    ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$port\$"
}

port_bound_publicly() {
    local port="$1"
    ss -tln 2>/dev/null | awk '{print $4}' | grep -E ":${port}\$" | grep -vqE '^(127\.0\.0\.1|\[::1\])'
}

storage_port_in_use_by_ours() {
    local port="$1"
    case "$port" in
        5432)
            systemctl is-active --quiet postgresql 2>/dev/null
            ;;
        6379)
            systemctl is-active --quiet redis-server 2>/dev/null
            ;;
        9000|9001)
            minio_container_running
            ;;
        *)
            return 1
            ;;
    esac
}

check_port_free() {
    local port="$1"
    local label="$2"
    if port_in_use "$port"; then
        if storage_port_in_use_by_ours "$port"; then
            log SKIP "Port $port ($label) dipakai service P5 milik installer — valid, tidak ada konflik"
            return 0
        fi
        die "Port $port ($label) sudah digunakan service lain. Tidak akan mengambil alih port service yang ada — resolusi manual diperlukan"
    fi
    log OK "Port $port ($label) bebas"
}

validate_storage_ports() {
    local p
    log INFO "Memeriksa konflik port storage (sebelum mengaktifkan service)..."
    for p in "${STORAGE_PORTS[@]}"; do
        check_port_free "$p" "storage"
    done
}

validate_storage_binding() {
    local p label
    log INFO "Memeriksa binding port storage (harus lokal, tidak publik)..."
    for p in "${STORAGE_PORTS[@]}"; do
        case "$p" in
            5432) label="PostgreSQL" ;;
            6379) label="Redis" ;;
            9000|9001) label="MinIO" ;;
            *) label="storage" ;;
        esac
        if ! port_in_use "$p"; then
            log WARN "Port $p ($label) tidak terdeteksi listening"
        elif port_bound_publicly "$p"; then
            log WARN "Port $p ($label) ter-bind ke interface publik — sebaiknya dibatasi ke 127.0.0.1"
        else
            log OK "Port $p ($label) ter-bind lokal (127.0.0.1)"
        fi
    done
}

run_p5() {
    log INFO "=== vps-setup | P5: PostgreSQL + Redis + MinIO ==="
    validate_storage_ports
    run_p5_postgres
    run_p5_redis
    run_p5_minio
    validate_storage_binding
    log INFO "P5 tidak membuat database/user project, tidak membuat password default, tidak expose storage ke internet"
    log OK "P5 PostgreSQL + Redis + MinIO selesai"
}