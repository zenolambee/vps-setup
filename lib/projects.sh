#!/usr/bin/env bash

# P8: Project requirements compatibility
#
# Memverifikasi bahwa runtime/tooling di VPS memenuhi kebutuhan project
# pengguna — TANPA clone repository, TANPA memasang dependency project,
# TANPA menyentuh source/.env/konfigurasi project.
#
# Cakupan: BotSpace, Content-Pilot, Toko-Online.
# MetaTrader dan MT-Info sengaja TIDAK termasuk.
#
# Semua fungsi bersifat read-only terhadap sistem, kecuali cache Corepack
# (cache package manager level sistem, bukan project).

export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

# --- Kebutuhan per project (deklaratif) ---

BOTSPACE_NODE_MIN="20"
BOTSPACE_PNPM="9.15.5"

CONTENT_PILOT_NODE_MIN="20.11"
CONTENT_PILOT_PNPM="10.34.5"

TOKO_ONLINE_NODE_MAJOR="20"
TOKO_ONLINE_NPM_MAJOR="10"

PROJ_PASS=0
PROJ_WARN=0
PROJ_DEP=0

# --- Helper ---

# PASS: kebutuhan terpenuhi oleh runtime sistem
proj_pass() {
    PROJ_PASS=$((PROJ_PASS + 1))
    log OK "PASS  | $1"
}

# WARN: belum terpenuhi / perlu perhatian — tidak ada perubahan otomatis
proj_warn() {
    PROJ_WARN=$((PROJ_WARN + 1))
    log WARN "WARN  | $1"
}

# SKIP: sengaja tidak ditangani P8 karena merupakan project dependency
proj_dep() {
    PROJ_DEP=$((PROJ_DEP + 1))
    log SKIP "DEP   | $1"
}

# Bandingkan versi bertitik: benar bila have >= want
proj_ver_ge() {
    local have="$1" want="$2"
    [[ -z "$have" || -z "$want" ]] && return 1
    [[ "$have" == "$want" ]] && return 0
    [[ "$(printf '%s\n%s\n' "$want" "$have" | sort -V | head -1)" == "$want" ]]
}

proj_node_version() {
    node --version 2>/dev/null | sed 's/^v//'
}

proj_npm_major() {
    npm --version 2>/dev/null | cut -d. -f1
}

# Apakah versi pnpm tertentu sudah ada di cache Corepack level sistem
proj_pnpm_cached() {
    local want="$1" cache
    cache="${COREPACK_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/node/corepack}"
    [[ -d "$cache/v1/pnpm/$want" ]]
}

# Verifikasi Corepack mampu menyediakan pnpm versi tertentu secara per-project.
# Probe dijalankan di direktori temporary — repository project TIDAK disentuh.
# pnpm global tetap apa adanya (tidak diganti, tidak di-downgrade).
proj_verify_pnpm_version() {
    local want="$1" label="$2" probe got global_before global_after
    global_before="$(pnpm --version 2>/dev/null || true)"

    if ! corepack_is_usable; then
        proj_warn "$label: pnpm $want tidak dapat diverifikasi — Corepack tidak tersedia"
        return 0
    fi

    if proj_pnpm_cached "$want"; then
        log INFO "$label: pnpm $want sudah ada di cache Corepack — verifikasi tanpa unduh ulang"
    else
        log INFO "$label: memverifikasi Corepack dapat menyediakan pnpm $want (unduh ke cache sistem, bukan ke project)..."
    fi

    probe="$(mktemp -d)"
    printf '{"name":"vps-setup-probe","private":true,"packageManager":"pnpm@%s"}\n' "$want" > "$probe/package.json"
    got="$(cd "$probe" && pnpm --version 2>/dev/null | tail -1 || true)"
    rm -rf "$probe"

    if [[ "$got" == "$want" ]]; then
        proj_pass "$label: Corepack menyediakan pnpm $want per-project (via field packageManager)"
    else
        proj_warn "$label: Corepack belum dapat menyediakan pnpm $want (terdeteksi: ${got:-tidak ada}) — periksa koneksi registry"
    fi

    global_after="$(pnpm --version 2>/dev/null || true)"
    if [[ "$global_before" == "$global_after" ]]; then
        log OK "pnpm global tetap ${global_after:-tidak ada} — tidak diganti, tidak di-downgrade"
    else
        proj_warn "pnpm global berubah dari $global_before ke $global_after — tidak diharapkan"
    fi
}

# --- BotSpace ---

validate_botspace_requirements() {
    local nodever
    log INFO "--- BotSpace ---"

    nodever="$(proj_node_version)"
    if [[ -z "$nodever" ]]; then
        proj_warn "BotSpace: Node.js tidak terdeteksi (butuh >= $BOTSPACE_NODE_MIN)"
    elif proj_ver_ge "$nodever" "$BOTSPACE_NODE_MIN"; then
        proj_pass "BotSpace: Node.js v$nodever memenuhi >= $BOTSPACE_NODE_MIN"
    else
        proj_warn "BotSpace: Node.js v$nodever < $BOTSPACE_NODE_MIN — jalankan P2; P8 tidak mengubah Node.js"
    fi

    proj_verify_pnpm_version "$BOTSPACE_PNPM" "BotSpace"

    # Turbo & TypeScript adalah devDependency monorepo, bukan runtime sistem.
    # Tidak diinstal global agar versi project tidak tertimpa.
    if command -v turbo >/dev/null 2>&1; then
        log INFO "BotSpace: turbo global terdeteksi ($(turbo --version 2>/dev/null || echo '?')) — tidak diubah; project tetap memakai versi dari devDependency"
    fi
    proj_dep "BotSpace: Turbo CLI = project dependency (devDependency monorepo, dijalankan via 'pnpm turbo'/'npx turbo'). Tidak diinstal global oleh P8"

    if command -v tsc >/dev/null 2>&1; then
        log INFO "BotSpace: tsc global terdeteksi ($(tsc --version 2>/dev/null || echo '?')) — tidak diubah; project tetap memakai versi dari devDependency"
    fi
    proj_dep "BotSpace: TypeScript = project dependency (devDependency, dijalankan via 'pnpm tsc'/'npx tsc'). Tidak diinstal global oleh P8"

    # Prasyarat runner untuk menjalankan tool per-project tanpa install global
    if npm_is_usable && command -v npx >/dev/null 2>&1; then
        proj_pass "BotSpace: runner per-project tersedia (npx $(npx --version 2>/dev/null || echo '?')) untuk Turbo/TypeScript tanpa instalasi global"
    else
        proj_warn "BotSpace: npx tidak tersedia — Turbo/TypeScript per-project tidak dapat dijalankan"
    fi
}

# --- Content-Pilot ---

validate_content_pilot_requirements() {
    local nodever
    log INFO "--- Content-Pilot ---"

    nodever="$(proj_node_version)"
    if [[ -z "$nodever" ]]; then
        proj_warn "Content-Pilot: Node.js tidak terdeteksi (butuh >= $CONTENT_PILOT_NODE_MIN)"
    elif proj_ver_ge "$nodever" "$CONTENT_PILOT_NODE_MIN"; then
        proj_pass "Content-Pilot: Node.js v$nodever memenuhi >= $CONTENT_PILOT_NODE_MIN"
    else
        proj_warn "Content-Pilot: Node.js v$nodever < $CONTENT_PILOT_NODE_MIN — jalankan P2; P8 tidak mengubah Node.js"
    fi

    proj_verify_pnpm_version "$CONTENT_PILOT_PNPM" "Content-Pilot"

    # Docker Engine + Compose v2 (P4)
    if docker_is_usable; then
        proj_pass "Content-Pilot: Docker Engine tersedia ($(docker --version 2>/dev/null))"
        if docker_service_active; then
            proj_pass "Content-Pilot: service docker aktif"
        else
            proj_warn "Content-Pilot: service docker tidak aktif — jalankan P4; P8 tidak mengubah service"
        fi
        if compose_is_usable; then
            proj_pass "Content-Pilot: Docker Compose v2 tersedia ($(docker compose version 2>/dev/null | head -1))"
        else
            proj_warn "Content-Pilot: Docker Compose v2 tidak tersedia — jalankan P4"
        fi
    else
        proj_warn "Content-Pilot: Docker Engine belum terpasang — jalankan P4; P8 tidak memasang Docker"
        proj_warn "Content-Pilot: Docker Compose v2 tidak dapat diverifikasi tanpa Docker Engine"
    fi

    validate_project_postgres "Content-Pilot"
    validate_project_redis "Content-Pilot"
    validate_project_minio "Content-Pilot"
}

# --- Toko-Online ---

validate_toko_online_requirements() {
    local nodever nodemajor npmmajor
    log INFO "--- Toko-Online ---"

    nodever="$(proj_node_version)"
    nodemajor="${nodever%%.*}"
    if [[ -z "$nodever" ]]; then
        proj_warn "Toko-Online: Node.js tidak terdeteksi (butuh $TOKO_ONLINE_NODE_MAJOR.x)"
    elif [[ "$nodemajor" == "$TOKO_ONLINE_NODE_MAJOR" ]]; then
        proj_pass "Toko-Online: Node.js v$nodever sesuai target $TOKO_ONLINE_NODE_MAJOR.x"
    elif [[ "$nodemajor" -gt "$TOKO_ONLINE_NODE_MAJOR" ]]; then
        proj_warn "Toko-Online: Node.js v$nodever lebih baru dari target $TOKO_ONLINE_NODE_MAJOR.x — tidak di-downgrade oleh P8. Jika project butuh $TOKO_ONLINE_NODE_MAJOR.x secara ketat, pakai version manager per-project (mis. nvm/Volta) tanpa mengubah Node global"
    else
        proj_warn "Toko-Online: Node.js v$nodever di bawah target $TOKO_ONLINE_NODE_MAJOR.x — jalankan P2"
    fi

    npmmajor="$(proj_npm_major)"
    if [[ -z "$npmmajor" ]]; then
        proj_warn "Toko-Online: npm tidak terdeteksi (butuh ${TOKO_ONLINE_NPM_MAJOR}.x)"
    elif [[ "$npmmajor" == "$TOKO_ONLINE_NPM_MAJOR" ]]; then
        proj_pass "Toko-Online: npm $(npm --version) sesuai target ${TOKO_ONLINE_NPM_MAJOR}.x"
    elif [[ "$npmmajor" -gt "$TOKO_ONLINE_NPM_MAJOR" ]]; then
        proj_warn "Toko-Online: npm $(npm --version) lebih baru dari target ${TOKO_ONLINE_NPM_MAJOR}.x — tidak di-downgrade oleh P8. Lockfile v3 tetap kompatibel; bila butuh npm ${TOKO_ONLINE_NPM_MAJOR}.x ketat, jalankan 'npx npm@${TOKO_ONLINE_NPM_MAJOR} ...' per-project"
    else
        proj_warn "Toko-Online: npm $(npm --version) di bawah target ${TOKO_ONLINE_NPM_MAJOR}.x — jalankan P2"
    fi

    validate_project_postgres "Toko-Online"
}

# --- Pemeriksaan service bersama (read-only) ---

# PostgreSQL: hanya command/service/koneksi lokal.
# Tidak membuat database, tidak mengubah password/konfigurasi.
validate_project_postgres() {
    local label="$1"
    if ! postgres_is_usable; then
        proj_warn "$label: PostgreSQL belum terpasang — jalankan P5; P8 tidak memasang PostgreSQL"
        return 0
    fi
    proj_pass "$label: PostgreSQL client tersedia ($(psql --version 2>/dev/null))"
    if postgres_service_active; then
        proj_pass "$label: service postgresql aktif"
    else
        proj_warn "$label: service postgresql tidak aktif — jalankan P5; P8 tidak mengubah service"
        return 0
    fi
    if pg_isready -h 127.0.0.1 -p "${PG_PORT:-5432}" >/dev/null 2>&1; then
        proj_pass "$label: PostgreSQL menerima koneksi lokal (pg_isready 127.0.0.1:${PG_PORT:-5432})"
    else
        proj_warn "$label: PostgreSQL tidak menerima koneksi lokal di port ${PG_PORT:-5432}"
    fi
    log INFO "$label: P8 tidak membuat database/user project, tidak mengubah password atau konfigurasi PostgreSQL"
}

# Redis: service + ping. Tidak menulis/menghapus data.
validate_project_redis() {
    local label="$1" pong
    if ! redis_is_usable; then
        proj_warn "$label: Redis belum terpasang — jalankan P5; P8 tidak memasang Redis"
        return 0
    fi
    proj_pass "$label: Redis tersedia ($(redis-server --version 2>/dev/null | awk '{print $1, $2, $3}'))"
    if ! redis_service_active; then
        proj_warn "$label: service redis-server tidak aktif — jalankan P5; P8 tidak mengubah service"
        return 0
    fi
    proj_pass "$label: service redis-server aktif"
    pong="$(redis-cli -h 127.0.0.1 -p "${REDIS_PORT:-6379}" ping 2>/dev/null || true)"
    if [[ "$pong" == "PONG" ]]; then
        proj_pass "$label: Redis merespons ping lokal (read-only, data tidak diubah)"
    else
        proj_warn "$label: redis-cli ping gagal di port ${REDIS_PORT:-6379} (jawaban: ${pong:-kosong})"
    fi
}

# MinIO: container/health endpoint existing. Credential dan bucket tidak disentuh.
validate_project_minio() {
    local label="$1"
    if ! command -v docker >/dev/null 2>&1; then
        proj_warn "$label: MinIO tidak dapat diverifikasi — Docker belum terpasang (jalankan P4/P5)"
        return 0
    fi
    if ! minio_container_exists; then
        proj_warn "$label: container MinIO (${MINIO_CONTAINER:-vps-minio}) belum ada — jalankan P5; P8 tidak membuat deployment"
        return 0
    fi
    if ! minio_container_running; then
        proj_warn "$label: container MinIO (${MINIO_CONTAINER:-vps-minio}) tidak berjalan — jalankan P5; P8 tidak menjalankan container"
        return 0
    fi
    proj_pass "$label: container MinIO berjalan (${MINIO_CONTAINER:-vps-minio})"
    if minio_endpoint_healthy; then
        proj_pass "$label: endpoint MinIO lokal sehat (127.0.0.1:${MINIO_API_PORT:-9000}/minio/health/live)"
    else
        proj_warn "$label: endpoint MinIO lokal belum merespons health check"
    fi
    log INFO "$label: P8 tidak membaca/mengubah credential MinIO dan tidak membuat/menghapus bucket"
}

# --- Orkestrator ---

validate_project_requirements() {
    PROJ_PASS=0
    PROJ_WARN=0
    PROJ_DEP=0
    validate_botspace_requirements
    validate_content_pilot_requirements
    validate_toko_online_requirements
    log INFO "Ringkasan kebutuhan project: PASS=$PROJ_PASS, WARN=$PROJ_WARN, DEP(project dependency)=$PROJ_DEP"
    if [[ "$PROJ_WARN" -gt 0 ]]; then
        log WARN "$PROJ_WARN kebutuhan belum terpenuhi — jalankan milestone terkait (P2/P4/P5). P8 tidak memasang atau mengubah apa pun"
    else
        log OK "Semua kebutuhan runtime sistem untuk BotSpace, Content-Pilot, dan Toko-Online terpenuhi"
    fi
}

run_p8() {
    log INFO "=== vps-setup | P8: Project Requirements Compatibility ==="
    log INFO "Cakupan: BotSpace, Content-Pilot, Toko-Online (MetaTrader/MT-Info tidak termasuk)"
    validate_project_requirements
    log INFO "P8 read-only terhadap project: tanpa clone repository, tanpa install dependency, tanpa mengubah source/.env/konfigurasi project"
    log OK "P8 Project Requirements Compatibility selesai"
}
