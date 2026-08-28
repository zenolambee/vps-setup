# vps-setup

Installer bertahap untuk VPS berbasis **Ubuntu/Debian**.
Idempotent dan aman dijalankan berulang kali.

## Status Milestone

- [x] P0: Foundation — validasi environment, system update, paket dasar
- [x] P1: Git + GitHub CLI
- [x] P2: Node.js 20 + npm + pnpm (Corepack)
- [x] P3: Python Environment
- [ ] P4+: Docker, PostgreSQL, Redis, MinIO, Caddy, OpenCode, MetaTrader —
      belum diimplementasikan

## Struktur

| Path | Keterangan |
|---|---|
| `setup.sh` | Entry point installer utama |
| `lib/common.sh` | Logging `[INFO]`/`[OK]`/`[WARN]`/`[ERROR]`/`[SKIP]`, error handling, trap |
| `lib/validators.sh` | Validasi root/sudo, OS, arsitektur, apt, disk, koneksi repository |
| `lib/packages.sh` | System update & instalasi paket dasar (idempotent) |
| `lib/git.sh` | P1: instalasi & validasi Git dan GitHub CLI |
| `lib/node.sh` | P2: instalasi & validasi Node.js 20, npm, pnpm/Corepack |
| `lib/python.sh` | P3: instalasi & validasi Python 3, pip, venv |
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

## Cakupan P2

- **Node.js 20** (target kompatibilitas: BotSpace `>=20` + pnpm 9.x,
  Content-Pilot `>=20.11` + pnpm 10.x, Toko Online `Node 20` + npm) —
  diinstal via repository resmi **NodeSource** `node_20.x` (metode apt,
  cocok untuk Ubuntu/Debian). Hanya satu versi Node yang diaktifkan.
  Jika versi Node aktif bukan 20, installer mengevaluasi keamanan
  (proses/systemd/dependensi) sebelum menggantinya.
- **npm** — bundled dengan Node.js 20; versi bawaan tidak dipaksakan.
- **pnpm** — dikelola via **Corepack** (bundled dengan Node.js 20).
  Tidak mengunci satu versi pnpm global: versi pnpm ditentukan
  **per-project** melalui field `packageManager` di `package.json`
  (mis. `pnpm@9.x` untuk BotSpace, `pnpm@10.x` untuk Content-Pilot),
  sehingga satu environment mampu menangani kedua major version.
- Validasi: `validate_node`, `validate_npm`, `validate_pnpm`,
  `validate_corepack`, pengecekan PATH & versi major.
- Idempotent: jika Node 20/npm/pnpm sudah benar, dilewati (`[SKIP]`).
- Tidak menginstal dependency project (tidak `npm install`/`pnpm install`,
  tidak build, tidak clone).

## Cakupan P3

- **Python 3** — menggunakan Python 3 stabil bawaan resmi Ubuntu/Debian
  (`/usr/bin/python3`). Tidak mengganti atau menghapus Python sistem.
  Menyiapkan environment universal untuk development, terutama bagian
  Python dari **MT-Info** (Telegram bridge/backtester).
- **pip** — dipasang melalui paket sistem `python3-pip` (metode aman untuk
  Ubuntu/Debian). Tidak menggunakan `sudo pip install` ke system Python;
  tidak menginstal dependency project apa pun.
- **venv** — memastikan `python3-venv` (ensurepip) tersedia; pengujian
  pembuatan virtual environment dilakukan di directory temporary dan
  dihapus kembali setelah test.
- **Build tools** — `python3-dev` dipasang hanya jika belum tersedia,
  untuk dukungan pembuatan native extension/wheel.
- Validasi: `validate_python` (`python3 --version`), `validate_pip`
  (`python3 -m pip --version`), `validate_venv` (buat venv, jalankan
  python & pip di dalamnya, lalu hapus).
- Idempotent: Python/pip/venv/dev yang sudah benar dilewati (`[SKIP]`).
- **MT-Info** hanya didukung pada sisi Python; **MetaTrader/MT5 sengaja
  tidak termasuk** dalam instalasi ini.

## Log

Semua aktivitas dicatat di `/var/log/vps-setup/setup.log`.
