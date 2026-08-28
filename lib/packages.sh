#!/usr/bin/env bash

PACKAGES_CONF="${ROOT:?ROOT tidak diset}/config/packages.conf"

package_is_installed() {
    local status
    status="$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null || true)"
    [[ "$status" == "install ok installed" ]]
}

read_package_list() {
    local pkg
    local list=()
    if [[ ! -f "$PACKAGES_CONF" ]]; then
        die "File konfigurasi paket tidak ditemukan: $PACKAGES_CONF"
    fi
    while IFS= read -r pkg || [[ -n "$pkg" ]]; do
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        list+=("$pkg")
    done < "$PACKAGES_CONF"
    printf '%s\n' "${list[@]}"
}

update_system() {
    log INFO "Melakukan upgrade paket sistem (apt-get upgrade)..."
    if ! apt-get upgrade -y >/dev/null 2>&1; then
        die "apt-get upgrade gagal. Periksa dengan 'apt-get upgrade' secara manual"
    fi
    log OK "Paket sistem berhasil di-upgrade"
}

install_base_packages() {
    local pkg
    local list
    list="$(read_package_list)"
    if [[ -z "$list" ]]; then
        die "Daftar paket di $PACKAGES_CONF kosong"
    fi
    local total
    total="$(grep -vcE '^\s*(#.*)?$' "$PACKAGES_CONF")"
    log INFO "Memeriksa $total paket dasar..."
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        if package_is_installed "$pkg"; then
            log SKIP "$pkg sudah terinstal, dilewati"
        else
            log INFO "Menginstal $pkg ..."
            if apt-get install -y "$pkg" >/dev/null 2>&1 && package_is_installed "$pkg"; then
                log OK "$pkg berhasil diinstal"
            else
                die "Gagal menginstal $pkg. Jalankan 'apt-get install -y $pkg' manual untuk detail"
            fi
        fi
    done <<< "$list"
}