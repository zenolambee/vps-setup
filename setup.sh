#!/usr/bin/env bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT

for lib in common validators packages git node; do
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
    log OK "vps-setup selesai: P0 Foundation + P1 Git/GitHub CLI + P2 Node.js 20/npm/pnpm terpasang."
}

main "$@"