# vps-setup

Installer bertahap untuk VPS berbasis **Ubuntu/Debian**.
Idempotent dan aman dijalankan berulang kali.

## Status Milestone

- [x] **P0: Foundation** — validasi environment, system update, paket dasar — *complete*
- [x] **P1: Git + GitHub CLI** — *complete*
- [x] **P2: Node.js 20 + npm + pnpm (Corepack)** — *complete*
- [x] **P3: Python Environment** — *complete*
- [x] **P4: Docker + Docker Compose v2** — *complete*
- [x] **P5: PostgreSQL + Redis + MinIO** — *complete*
- [x] **P6: Caddy Reverse Proxy + HTTPS Foundation** — *complete*
- [ ] **P7: OpenCode** — *pending*
- [ ] P8+: monitoring, deployment tooling — *pending*

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
| `lib/docker.sh` | P4: instalasi & validasi Docker Engine + Docker Compose v2 |
| `lib/postgres.sh` | P5: instalasi & validasi PostgreSQL |
| `lib/redis.sh` | P5: instalasi & validasi Redis |
| `lib/minio.sh` | P5: deployment & validasi MinIO (Docker, image resmi) |
| `lib/storage.sh` | P5: cek konflik/binding port storage + orkestrator P5 |
| `lib/caddy.sh` | P6: instalasi, konfigurasi foundation, service, port safety & validasi Caddy |
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

## Cakupan P4

- **Docker Engine** — diinstal dari repository resmi Docker
  (`download.docker.com`) dengan metode keyring modern dan aman.
  Tidak menggunakan `curl | sh` dari sumber tidak resmi.
  Jika Docker sudah terpasang dari sumber resmi, dilewati (`[SKIP]`).
  Container/image/volume/network/config milik pengguna tidak dihapus,
  tidak ada reset Docker.
- **Docker Compose v2** — melalui plugin `docker compose`
  (`docker-compose-plugin`). Compose v1 (`docker-compose` Python package)
  tidak dipasang.
- **Service** — memastikan `docker` aktif (`systemctl enable --now docker`
  hanya jika belum aktif); tidak ada restart service/VPS yang tidak perlu.
- **User access** — user non-root development yang terdeteksi (UID>=1000)
  ditambahkan ke group `docker`; group yang ada tidak dihapus/diubah;
  root tetap dapat menggunakan Docker. Perubahan group berlaku pada
  session baru, tanpa logout paksa.
- Validasi: `validate_docker` (`docker --version`, `docker info`),
  `validate_compose` (`docker compose version`), `validate_docker_service`
  (service aktif + daemon dapat diakses), validasi konfigurasi compose
  sederhana, dan test container ringan resmi (`hello-world`) di lingkungan
  terisolasi — semua resource test dibersihkan.
- **Keamanan**: tidak ada expose Docker API TCP, tidak ada port daemon
  terbuka, tidak ada remote API, tidak ada insecure config, tidak ada
  perubahan firewall.
- P4 tidak menjalankan project dan tidak clone repository; tidak ada tool
  P5+ (PostgreSQL/Redis/MinIO/Caddy/OpenCode) yang dipasang.

## Cakupan P5

- **PostgreSQL** (Toko Online butuh 14+, Content-Pilot memakai PostgreSQL +
  Prisma) — dipasang dari paket resmi Ubuntu/Debian (`postgresql`,
  `postgresql-client`; pada Ubuntu 24.04 = PostgreSQL 16). Service systemd
  `postgresql` diaktifkan (`enable --now` hanya jika belum aktif) dan
  enabled untuk boot. Health check: `pg_isready -h 127.0.0.1 -p 5432`.
  Installer **tidak** membuat database/user project dan tidak menetapkan
  password apa pun.
- **Redis** — dipasang dari paket resmi Ubuntu/Debian (`redis-server`).
  Service systemd `redis-server`, bind default lokal (127.0.0.1) tidak
  diubah; tidak expose ke internet; tidak membuka firewall. Health check:
  `redis-cli -h 127.0.0.1 ping` → `PONG`.
- **MinIO** — object storage S3-compatible untuk Content-Pilot. Deployment
  generik standalone via **Docker Compose** (image resmi `minio/minio` dari
  Docker Hub, tidak bergantung pada repository project), persistent volume
  `minio-data`, container `vps-minio`, restart policy `unless-stopped`.
  API `127.0.0.1:9000`, console `127.0.0.1:9001` (lokal saja, tidak
  dipublikasikan). Credential access key/secret key dibuat acak saat
  runtime dan disimpan di `/etc/minio/minio.env` (mode 600) — tidak ada
  credential di source code, tidak dicetak ke log.
- **Port** — konflik port dicek sebelum service diaktifkan (5432, 6379,
  9000, 9001); port yang dipakai service lain tidak akan diambil alih.
  Binding port diverifikasi lokal setelah deploy.
- Validasi: `validate_postgres`, `validate_redis`, `validate_minio`,
  `validate_storage_ports`, `validate_minio_storage`.
- Idempotent: service yang sudah benar dilewati (`[SKIP]`); tidak ada
  duplicate container/volume; data, database, volume, dan credential
  existing tidak dihapus/diubah.
- Installer tidak membuat database project, tidak menjalankan migration,
  dan tidak clone repository.

## Cakupan P6

**Caddy Reverse Proxy & HTTPS Foundation** — hanya *foundation*. P6 menyiapkan
web server yang siap dipakai sebagai reverse proxy, tanpa mengonfigurasi domain
atau route project apa pun.

### Instalasi

- **Sumber resmi** — repository resmi Caddy (Cloudsmith) dengan keyring GPG
  (`/usr/share/keyrings/caddy-stable-archive-keyring.gpg`), metode apt yang
  didukung untuk Ubuntu/Debian. Tidak ada `curl | sh`.
- **Instalasi existing dipakai apa adanya** — jika `caddy version` berhasil,
  instalasi yang ada dipertahankan (`[SKIP]`), tanpa reinstall dan tanpa
  menambahkan repository. Repository hanya disiapkan saat Caddy benar-benar
  belum ada.

### Konfigurasi

- `/etc/caddy/Caddyfile` **tidak pernah ditimpa**. File hanya dibuat jika belum
  ada, dengan konfigurasi foundation: admin API `localhost:2019`, `import`
  dari `conf.d`, dan `:80` dengan endpoint `/healthz` + pesan placeholder.
- `/etc/caddy/conf.d/` disiapkan sebagai tempat **site block per-domain**
  (satu file per domain) untuk milestone deployment berikutnya. Isi direktori
  yang sudah ada tidak dibaca ulang, tidak diubah, tidak dihapus.
- Konfigurasi valid **tanpa membutuhkan domain**: `caddy validate` berhasil
  dengan `conf.d` kosong maupun setelah site block berdomain ditambahkan.
- Tidak ada domain project, route BotSpace/Content-Pilot/Toko Online/MT-Info,
  perubahan DNS, sertifikat manual, maupun TLS self-signed.

### HTTPS foundation

- Automatic HTTPS Caddy dibiarkan aktif (tidak ada `auto_https off`).
  Saat site block berdomain ditambahkan ke `conf.d`, Caddy menerbitkan
  sertifikat ACME dan mengaktifkan redirect HTTP→HTTPS secara otomatis —
  tanpa perubahan pada `Caddyfile` utama.
- Storage sertifikat (`/var/lib/caddy/.local/share/caddy`, owner service user
  `caddy`) diverifikasi siap. P6 tidak menerbitkan sertifikat apa pun.

### Port safety (80/443)

- Port 80 dan 443 diperiksa **sebelum dan sesudah** konfigurasi: process
  pemilik, alamat bind, dan container Docker yang mempublikasikan port.
- Jika port dipegang process/container lain: warning ditampilkan, port
  **tidak diambil alih**, process/container **tidak dihentikan**, service Caddy
  tidak diaktifkan — namun binary dan konfigurasi Caddy tetap divalidasi.

### Service

- `systemctl enable --now caddy` hanya dijalankan bila service belum aktif
  **dan** port 80/443 aman. Service yang sudah sehat tidak direstart/di-reload
  hanya untuk validasi. Tidak ada restart service lain, tidak ada reboot VPS.

### Keamanan

- Admin API dibatasi ke `localhost:2019` dan diverifikasi tidak ter-bind ke
  interface publik; service `caddy-api` tidak diaktifkan.
- PostgreSQL (5432), Redis (6379), MinIO (9000/9001), dan Docker API
  (2375/2376) diverifikasi tetap privat — P6 tidak membuat reverse proxy ke
  backend mana pun dan tidak mengubah konfigurasi P4/P5.
- Tidak ada credential, token, domain, atau private key di repository.

### Validasi

| Fungsi | Cakupan |
|---|---|
| `validate_caddy` | `caddy version`, path binary |
| `validate_caddy_config` | `caddy validate --config`, jumlah file `conf.d` |
| `validate_caddy_ports` | listener, process owner, bind address, container port 80/443 |
| `validate_caddy_service` | unit systemd, status active, boot state, MainPID/user |
| `validate_caddy_admin_security` | admin API tidak terekspos publik |
| `validate_caddy_backend_isolation` | port backend P4/P5 tetap privat |
| `validate_caddy_https_foundation` | storage sertifikat ACME, automatic HTTPS aktif |
| `validate_caddy_local_http` | HTTP lokal `127.0.0.1:80` (hanya jika port 80 milik Caddy) |

### Idempotency

Run kedua exit 0 tanpa reinstall, tanpa menimpa konfigurasi, tanpa duplikasi
site block, tanpa mengambil alih port, dan tanpa restart service.

P6 tidak melakukan deployment project, tidak clone repository, dan tidak
memasang tool P7+ (OpenCode, monitoring, deployment tooling).

## Log

Semua aktivitas dicatat di `/var/log/vps-setup/setup.log`.
