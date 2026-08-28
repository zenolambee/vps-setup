#!/usr/bin/env bash

PY_VENV_TEST_DIR="${TMPDIR:-/tmp}/vps-setup-venv-test"

python_is_usable() {
    command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1
}

pip_is_usable() {
    python3 -m pip --version >/dev/null 2>&1
}

venv_module_ok() {
    python3 -c "import ensurepip" >/dev/null 2>&1
}

install_python() {
    if python_is_usable; then
        log SKIP "Python sudah tersedia: $(python3 --version) di $(command -v python3)"
        return 0
    fi
    log INFO "Menginstal python3 (paket sistem Ubuntu/Debian)..."
    if ! apt-get install -y python3 >/dev/null 2>&1 || ! python_is_usable; then
        die "Gagal menyediakan python3. Periksa dengan 'apt-get install -y python3' manual"
    fi
    log OK "Python tersedia: $(python3 --version)"
}

install_pip() {
    if pip_is_usable; then
        log SKIP "pip sudah tersedia: $(python3 -m pip --version)"
        return 0
    fi
    log INFO "Menginstal python3-pip (metode aman via apt, tanpa sudo pip install)..."
    if ! apt-get install -y python3-pip >/dev/null 2>&1 || ! pip_is_usable; then
        die "Gagal menginstal python3-pip. Periksa dengan 'apt-get install -y python3-pip' manual"
    fi
    log OK "pip tersedia: $(python3 -m pip --version)"
}

install_venv() {
    if venv_module_ok; then
        log SKIP "python3-venv (ensurepip) sudah tersedia"
        return 0
    fi
    log INFO "Menginstal python3-venv..."
    if ! apt-get install -y python3-venv >/dev/null 2>&1 || ! venv_module_ok; then
        die "Gagal menginstal python3-venv. Periksa dengan 'apt-get install -y python3-venv' manual"
    fi
    log OK "python3-venv terinstal"
}

install_python_dev() {
    local pkg="python3-dev"
    local status
    status="$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)"
    if [[ "$status" == "install ok installed" ]]; then
        log SKIP "$pkg sudah terinstal"
        return 0
    fi
    log INFO "Menginstal $pkg (header/alat build Python untuk native extension)..."
    if ! apt-get install -y "$pkg" >/dev/null 2>&1; then
        die "Gagal menginstal $pkg. Periksa dengan 'apt-get install -y $pkg' manual"
    fi
    log OK "$pkg terinstal"
}

validate_python() {
    if ! python_is_usable; then
        die "python3 tidak terdeteksi"
    fi
    log OK "python3 terdeteksi: $(python3 --version) di $(command -v python3)"
}

validate_pip() {
    local ver
    ver="$(python3 -m pip --version 2>/dev/null || true)"
    if [[ -z "$ver" ]]; then
        die "pip tidak terdeteksi (python3 -m pip gagal)"
    fi
    log OK "pip terdeteksi: $ver"
}

validate_venv() {
    local venv_dir="$PY_VENV_TEST_DIR"
    local py_out pip_out
    log INFO "Menguji pembuatan virtual environment di $venv_dir (temporary)..."
    rm -rf "$venv_dir"
    if ! python3 -m venv "$venv_dir" >/dev/null 2>&1; then
        rm -rf "$venv_dir"
        die "Gagal membuat virtual environment. Periksa dengan 'python3 -m venv $venv_dir' manual"
    fi
    py_out="$("$venv_dir/bin/python" --version 2>&1 || true)"
    pip_out="$("$venv_dir/bin/pip" --version 2>&1 || true)"
    if [[ -z "$py_out" || -z "$pip_out" ]]; then
        rm -rf "$venv_dir"
        die "venv dibuat namun python/pip di dalamnya tidak berjalan"
    fi
    log OK "venv berfungsi: $py_out"
    log OK "pip dalam venv berfungsi: $pip_out"
    rm -rf "$venv_dir"
    log INFO "Directory test venv ($venv_dir) dihapus"
}

run_p3() {
    log INFO "=== vps-setup | P3: Python Environment ==="
    install_python
    install_pip
    install_venv
    install_python_dev
    validate_python
    validate_pip
    validate_venv
    log INFO "MT-Info didukung pada sisi Python; MetaTrader/MT5 tidak termasuk dalam instalasi ini"
    log OK "P3 Python Environment selesai"
}