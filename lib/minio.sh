#!/usr/bin/env bash

MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_CONTAINER="vps-minio"
MINIO_IMAGE="minio/minio:latest"
MINIO_COMPOSE_DIR="/etc/minio"
MINIO_COMPOSE_FILE="$MINIO_COMPOSE_DIR/docker-compose.yml"
MINIO_ENV_FILE="$MINIO_COMPOSE_DIR/minio.env"
MINIO_VOLUME="minio-data"

minio_container_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$MINIO_CONTAINER"
}

minio_container_exists() {
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$MINIO_CONTAINER"
}

minio_endpoint_healthy() {
    curl -fsS "http://127.0.0.1:$MINIO_API_PORT/minio/health/live" >/dev/null 2>&1
}

generate_secret() {
    local len="$1"
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$len" || true
}

ensure_minio_credentials() {
    if [[ -f "$MINIO_ENV_FILE" ]] && grep -q '^MINIO_ROOT_USER=' "$MINIO_ENV_FILE" && grep -q '^MINIO_ROOT_PASSWORD=' "$MINIO_ENV_FILE"; then
        log SKIP "Credential MinIO lokal sudah ada (tidak diubah, tidak dicetak)"
        return 0
    fi
    mkdir -p "$MINIO_COMPOSE_DIR"
    log INFO "Membuat credential MinIO lokal (acak, permission ketat, tidak dicetak)..."
    {
        printf 'MINIO_ROOT_USER=%s\n' "$(generate_secret 16)"
        printf 'MINIO_ROOT_PASSWORD=%s\n' "$(generate_secret 32)"
    } > "$MINIO_ENV_FILE"
    chmod 600 "$MINIO_ENV_FILE"
    log OK "Credential MinIO lokal dibuat: $MINIO_ENV_FILE (mode 600)"
}

write_minio_compose() {
    cat > "$MINIO_COMPOSE_FILE" <<EOF
services:
  minio:
    image: $MINIO_IMAGE
    container_name: $MINIO_CONTAINER
    command: server /data --console-address ":9001"
    restart: unless-stopped
    env_file:
      - $MINIO_ENV_FILE
    ports:
      - "127.0.0.1:$MINIO_API_PORT:9000"
      - "127.0.0.1:$MINIO_CONSOLE_PORT:9001"
    volumes:
      - $MINIO_VOLUME:/data

volumes:
  $MINIO_VOLUME:
EOF
}

ensure_minio_deployment() {
    if minio_container_running; then
        log SKIP "Container MinIO sudah berjalan ($MINIO_CONTAINER)"
        return 0
    fi
    mkdir -p "$MINIO_COMPOSE_DIR"
    if [[ ! -f "$MINIO_COMPOSE_FILE" ]]; then
        log INFO "Membuat deployment MinIO standalone (image resmi $MINIO_IMAGE, sumber: Docker Hub) di $MINIO_COMPOSE_FILE..."
        write_minio_compose
        chmod 600 "$MINIO_COMPOSE_FILE"
        log OK "Deployment MinIO dibuat: $MINIO_COMPOSE_FILE"
    fi
    log INFO "Menjalankan MinIO (docker compose up -d)..."
    if ! docker compose -f "$MINIO_COMPOSE_FILE" up -d >/dev/null 2>&1; then
        die "Gagal menjalankan MinIO via docker compose. Periksa 'docker compose -f $MINIO_COMPOSE_FILE up -d' manual"
    fi
    local i
    for i in $(seq 1 30); do
        if minio_container_running; then
            break
        fi
        sleep 1
    done
    if ! minio_container_running; then
        die "Container $MINIO_CONTAINER tidak berjalan setelah docker compose up -d"
    fi
    log OK "Container MinIO berjalan ($MINIO_CONTAINER)"
}

validate_minio() {
    local i
    if ! minio_container_exists; then
        die "Container MinIO tidak ditemukan ($MINIO_CONTAINER)"
    fi
    if ! minio_container_running; then
        die "Container MinIO tidak berjalan"
    fi
    log OK "Container MinIO berjalan: $(docker inspect -f '{{.State.Status}}' "$MINIO_CONTAINER" 2>/dev/null || echo running)"
    for i in $(seq 1 30); do
        if minio_endpoint_healthy; then
            log OK "Endpoint MinIO lokal sehat: http://127.0.0.1:$MINIO_API_PORT/minio/health/live"
            return 0
        fi
        sleep 1
    done
    log WARN "Endpoint MinIO belum merespons health check dalam 30 detik — container tetap berjalan, cek log container"
}

validate_minio_storage() {
    local vol
    vol="$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' "$MINIO_CONTAINER" 2>/dev/null || true)"
    if [[ -n "$vol" ]]; then
        log OK "Persistent volume MinIO aktif: $vol"
    else
        log WARN "Tidak ada volume persistent terdeteksi pada container MinIO"
    fi
}

run_p5_minio() {
    log INFO "--- MinIO ---"
    ensure_minio_credentials
    ensure_minio_deployment
    validate_minio
    validate_minio_storage
}