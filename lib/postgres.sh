#!/usr/bin/env bash

PG_PORT=5432

postgres_is_usable() {
    command -v psql >/dev/null 2>&1 && command -v pg_isready >/dev/null 2>&1
}

postgres_service_active() {
    systemctl is-active --quiet postgresql
}

postgres_service_enabled() {
    systemctl is-enabled --quiet postgresql 2>/dev/null
}

postgres_major() {
    psql --version 2>/dev/null | sed -E 's/.* ([0-9]+)\..*/\1/'
}

install_postgres() {
    if postgres_is_usable; then
        log SKIP "PostgreSQL sudah tersedia: $(psql --version)"
        return 0
    fi
    log INFO "Menginstal PostgreSQL (paket resmi Ubuntu/Debian)..."
    if ! apt-get install -y postgresql postgresql-client >/dev/null 2>&1; then
        die "Gagal menginstal PostgreSQL. Periksa dengan 'apt-get install -y postgresql postgresql-client' manual"
    fi
    if ! postgres_is_usable; then
        die "PostgreSQL tidak terdeteksi setelah instalasi"
    fi
    log OK "PostgreSQL berhasil diinstal: $(psql --version)"
}

ensure_postgres_service() {
    if postgres_service_active; then
        log SKIP "Service postgresql sudah aktif"
    else
        log INFO "Mengaktifkan dan memulai service postgresql (systemctl enable --now postgresql)..."
        if ! systemctl enable --now postgresql >/dev/null 2>&1; then
            die "Gagal mengaktifkan service postgresql"
        fi
        if ! postgres_service_active; then
            die "Service postgresql tidak aktif setelah diaktifkan"
        fi
        log OK "Service postgresql aktif"
    fi
    if postgres_service_enabled; then
        log OK "postgresql sudah enabled untuk boot"
    else
        log INFO "Mengaktifkan postgresql untuk boot..."
        if ! systemctl enable postgresql >/dev/null 2>&1; then
            log WARN "Gagal enable postgresql untuk boot"
        else
            log OK "postgresql enabled untuk boot"
        fi
    fi
}

validate_postgres() {
    local ver major
    if ! postgres_is_usable; then
        die "PostgreSQL tidak terdeteksi"
    fi
    ver="$(psql --version 2>&1)"
    major="$(postgres_major || true)"
    log OK "PostgreSQL terdeteksi: $ver"
    if [[ -n "$major" && "$major" -lt 14 ]]; then
        die "PostgreSQL major $major < 14 — tidak memenuhi kebutuhan Toko Online (14+)"
    fi
    if ! pg_isready -h 127.0.0.1 -p "$PG_PORT" >/dev/null 2>&1; then
        die "pg_isready gagal — server PostgreSQL tidak menerima koneksi lokal di port $PG_PORT"
    fi
    log OK "PostgreSQL menerima koneksi lokal (pg_isready -h 127.0.0.1 -p $PG_PORT)"
}

run_p5_postgres() {
    log INFO "--- PostgreSQL ---"
    install_postgres
    ensure_postgres_service
    validate_postgres
}