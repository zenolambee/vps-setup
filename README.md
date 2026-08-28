# vps-setup

Installer bertahap untuk VPS berbasis **Ubuntu/Debian**.
Idempotent dan aman dijalankan berulang kali.

## Status Milestone

- [x] P0: Foundation — validasi environment, system update, paket dasar
- [x] P1: Git + GitHub CLI
- [ ] P2+: Node.js/npm/pnpm, Python, Docker, PostgreSQL, Redis, MinIO,
      Caddy, OpenCode, MetaTrader — belum diimplementasikan

## Struktur

| Path | Keterangan |
|---|---|
| `setup.sh` | Entry point installer utama |
| `lib/common.sh` | Logging `[INFO]`/`[OK]`/`[WARN]`/`[ERROR]`/`[SKIP]`, error handling, trap |
| `lib/validators.sh` | Validasi root/sudo, OS, arsitektur, apt, disk, koneksi repository |
| `lib/packages.sh` | System update & instalasi paket dasar (idempotent) |
| `lib/git.sh` | P1: instalasi & validasi Git dan GitHub CLI |
| `config/packages.conf` | Daftar paket dasar P0 (satu per baris) |

## Penggunaan

```bash
sudo bash setup.sh
```

Setiap komponen berikutnya (P2+) ditambahkan sebagai modul baru di `lib/`
dan dipanggil dari `setup.sh` — tanpa merombak struktur yang ada.

## Cakupan P0

- Validasi sebelum perubahan: root/sudo, OS (Ubuntu/Debian), arsitektur
  (amd64/arm64), package manager (apt-get), proses apt lain, ruang disk,
  koneksi repository (`apt-get update`)
- `apt-get update` + `apt-get upgrade`
- Paket dasar: `curl`, `wget`, `ca-certificates`, `gnupg`, `unzip`, `tar`,
  `jq`, `build-essential`
- Paket yang sudah terinstal dilewati (`[SKIP]`), tidak diinstal ulang

## Cakupan P1

- Instalasi **Git** jika belum tersedia (paket `git` dari apt)
- Instalasi **GitHub CLI (`gh`)** jika belum tersedia, menggunakan repository
  resmi GitHub CLI (`https://cli.github.com/packages`) yang sesuai untuk
  Ubuntu/Debian
- Validasi: `git --version`, `gh --version`, pengecekan executable/path,
  pengecekan konfigurasi dasar Git global **tanpa menimpa konfigurasi user**
- Tidak melakukan `gh auth login` otomatis; tidak membuat/menyimpan token
- Idempotent: jika Git/`gh` sudah terpasang dengan benar, dilewati (`[SKIP]`)

## Log

Semua aktivitas dicatat di `/var/log/vps-setup/setup.log`.
