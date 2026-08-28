#!/usr/bin/env bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT

for lib in common validators packages git node python docker postgres redis minio storage caddy tools; do
    source "$ROOT/lib/$lib.sh"
done

main() {
    setup_logging
    log INFO "=== vps-setup | P0: Foundation ==="
    log INFO "Memvalidasi environment sistem..."
    check_root
    check_os
    check_arch
    check_pkg_manager
    check_apt_process
    check_disk_space
    check_pkg_repo
    log OK "Semua validasi environment berhasil"
    update_system
    install_base_packages
    log OK "P0 Foundation selesai. Semua paket dasar terpasang."
    run_p1
    run_p2
    run_p3
    run_p4
    run_p5
    run_p6
    run_p7
    log OK "vps-setup selesai: P0-P7 terpasang (Foundation, Git/GitHub CLI, Node.js 20, Python, Docker, PostgreSQL/Redis/MinIO, Caddy, Developer/AI CLI tools)."
}

main "$@"