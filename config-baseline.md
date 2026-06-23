# Config Baseline — Order Processing Service

> **FP Teknologi Komputasi Awan 2026 — Kelompok B01**  
> Konfigurasi ini adalah **baseline** (titik awal pengukuran performa) sebelum dilakukan optimasi atau scale-out.

---

## 1. Ringkasan Arsitektur

```
Klien / Locust
      │
      ▼ HTTP :80
┌─────────────────────────────────────────────────────┐
│                  DigitalOcean Droplet                │
│   ┌──────────┐    ┌────────────────┐    ┌────────┐  │
│   │  Nginx   │───▶│ Gunicorn+Flask │───▶│ Mongo  │  │
│   │ (proxy)  │    │  8w × 2t       │    │  7.0   │  │
│   └──────────┘    └────────────────┘    └────────┘  │
│     port 80           port 5000        port 27017   │
│              (internal Docker network)               │
└─────────────────────────────────────────────────────┘
```

- **Tidak ada load balancer** — Nginx hanya berperan sebagai reverse proxy.
- **Semua komponen** (Nginx, Flask, MongoDB) berjalan di **satu VM** dalam container Docker.
- Komunikasi antar service melalui Docker bridge network `app_net` (subnet 172.20.0.0/24).

---

## 2. Spesifikasi Hardware (VM)

| Komponen | Detail |
|----------|--------|
| **Provider** | DigitalOcean |
| **Tipe** | Droplet (Basic) |
| **vCPU** | 4 vCPU |
| **RAM** | 8 GB |
| **Disk** | 160 GB SSD |
| **OS** | Ubuntu 24.04 LTS |
| **Harga** | **$48 / bulan** |
| **Jumlah VM** | **1 VM** (all-in-one) |
| **Total Biaya** | **$48 / bulan** |

---

## 3. Stack Teknologi

| Layer | Teknologi | Versi |
|-------|-----------|-------|
| Reverse Proxy | **Nginx** | 1.25 (Alpine) |
| WSGI Server | **Gunicorn** | 23.0.0 |
| Backend | **Flask** (Python) | 3.0.3 |
| Database | **MongoDB** | 7.0 |
| Container Runtime | **Docker + Compose** | Latest |
| Auth | **PyJWT + bcrypt** | 2.9.0 / 4.2.0 |

---

## 4. Detail Konfigurasi Per Komponen

### 4.1 Nginx — Reverse Proxy

> **Peran:** Menerima semua traffic HTTP dari luar dan meneruskannya ke backend Flask. Juga melayani file frontend statis.

| Parameter | Nilai | Keterangan |
|-----------|-------|------------|
| `worker_processes` | `auto` (2) | Auto-detect jumlah CPU core |
| `worker_connections` | 1024 | Max koneksi per worker |
| `keepalive_timeout` | 75s | Persistent connection klien |
| `keepalive_requests` | 1000 | Max request per koneksi |
| `gzip` | on (level 4) | Kompresi JSON response |
| `proxy_read_timeout` | 120s | Timeout tunggu backend |
| `upstream keepalive` | 32 | Koneksi persistent ke backend |
| Port expose | **80** | Satu-satunya port publik |
| Load balancing | **Tidak ada** | Single upstream `backend:5000` |

**Topologi upstream:**
```nginx
upstream flask_backend {
    server backend:5000;   # hanya 1 server — tidak ada LB
    keepalive 32;
}
```

---

### 4.2 Gunicorn — WSGI Server

> **Peran:** Menjalankan aplikasi Flask dengan banyak worker untuk melayani request secara paralel.

| Parameter | Nilai | Keterangan |
|-----------|-------|------------|
| `--workers` | **8** | (2 × vCPU) + 1 = 9, dipakai 8 untuk headroom |
| `--threads` | **2** | Per worker → total slot = 8 × 2 = **16 concurrent** |
| `--worker-class` | `gthread` | I/O-bound: cocok untuk request DB |
| `--timeout` | 120s | Worker restart jika tidak respond |
| `--bind` | `0.0.0.0:5000` | Internal network |
| Total concurrency | **16 slot** | 8 workers × 2 threads |

**Rumus workers:**
```
Rumus standar: (2 × vCPU) + 1 = 9
Dipakai 8 workers untuk menyisakan RAM untuk MongoDB
```

---

### 4.3 MongoDB — Database

> **Peran:** Menyimpan semua data (users, products, orders, audit_logs).

| Parameter | Nilai | Keterangan |
|-----------|-------|------------|
| Versi | **7.0** | LTS |
| `wiredTigerCacheSizeGB` | **2 GB** | Cache MongoDB (50% RAM yang dialokasikan) |
| Port | 27017 | Internal only (tidak expose ke host) |
| Auth | username/password | `MONGO_INITDB_ROOT_USERNAME/PASSWORD` |
| Storage | Docker volume `mongo_data` | Persistent |
| Database | `orderdb` | Collections: users, products, orders, audit_logs |

**Collections & Index yang disarankan:**
```
orders     → index: created_at (DESCENDING), order_id (UNIQUE)
products   → index: is_active, category
users      → index: email (UNIQUE)
```

---

### 4.4 Alokasi Memory (RAM 8 GB)

| Komponen | Limit | Reserved | Estimasi Aktual |
|----------|-------|----------|-----------------|
| **MongoDB** | 3 GB | 512 MB | ~2–3 GB |
| **Gunicorn + Flask** | 3 GB | 256 MB | ~800 MB–1.5 GB |
| **Nginx** | 256 MB | 64 MB | ~20–50 MB |
| **Docker daemon + OS** | — | — | ~300–500 MB |
| **Total** | ~6.5 GB soft limit | — | **≤ 8 GB** |

> ✅ Alokasi cukup longgar. MongoDB WiredTiger cache 2 GB memungkinkan sebagian besar working-set data tersimpan di memori, mengurangi disk I/O secara signifikan.

---

## 5. File Konfigurasi

| File | Lokasi | Fungsi |
|------|--------|--------|
| `docker-compose-baseline.yml` | `/` root project | Orkestrasi semua container |
| `.env` | `/` root project | Environment variables (secret) |
| `nginx.conf` | `/` root project | Konfigurasi Nginx reverse proxy |
| `Resources/BE/Dockerfile` | `Resources/BE/` | Build image backend Flask |

---

## 6. Environment Variables

| Variable | Default / Nilai | Keterangan |
|----------|-----------------|------------|
| `MONGO_URI` | `mongodb://admin:***@mongo:27017/orderdb?authSource=admin` | URI koneksi MongoDB |
| `JWT_SECRET` | (string acak panjang) | Secret key untuk signing JWT |
| `JWT_EXPIRES` | 86400 | Masa berlaku token (detik = 24 jam) |
| `GUNICORN_WORKERS` | 8 | Jumlah worker process |
| `GUNICORN_THREADS` | 2 | Thread per worker |
| `GUNICORN_WORKER_CLASS` | gthread | Tipe worker Gunicorn |
| `GUNICORN_TIMEOUT` | 120 | Timeout worker (detik) |

---

## 7. Port Mapping

| Service | Internal Port | External Port | Aksesibel dari |
|---------|--------------|---------------|----------------|
| Nginx | 80 | **80** | Internet (publik) |
| Flask/Gunicorn | 5000 | — | Internal network only |
| MongoDB | 27017 | — | Internal network only |

---

## 8. Cara Deploy

### Prasyarat di VM
```bash
# Install Docker & Docker Compose
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER
newgrp docker
```

### Clone & Setup
```bash
git clone https://github.com/<org>/FP-TKA-B01.git
cd FP-TKA-B01

# Edit password dan JWT_SECRET sesuai kebutuhan
nano .env
```

### Build & Run
```bash
# Build image backend dan jalankan semua service
docker compose -f docker-compose-baseline.yml up -d --build

# Cek status container
docker compose -f docker-compose-baseline.yml ps

# Lihat log real-time
docker compose -f docker-compose-baseline.yml logs -f
```

### Restore Database Dump
```bash
# Copy dump ke dalam container MongoDB
docker cp Resources/DB/dump fp_mongo_baseline:/tmp/dump

# Restore
docker exec fp_mongo_baseline mongorestore \
  --uri="mongodb://admin:MongoSecurePass@2026@localhost:27017" \
  --authSource=admin \
  --drop /tmp/dump
```

### Verifikasi
```bash
# Test health endpoint
curl http://localhost/health

# Test API endpoint
curl http://localhost/products
```

---

## 9. Estimasi Performa Baseline

> Angka berikut adalah **estimasi teoritis** sebelum dilakukan load testing sesungguhnya.

| Metrik | Estimasi Baseline |
|--------|-------------------|
| Gunicorn concurrent slots | **16** (8 workers × 2 threads) |
| Nginx max connections | ~4096 (4 workers × 1024) |
| Target RPS (GET sederhana) | ~150–400 RPS |
| Target RPS (POST order) | ~80–200 RPS |
| Bottleneck utama | MongoDB (single instance, WiredTiger cache 2 GB) |

---

## 10. Keterbatasan Baseline & Rencana Optimasi

| Keterbatasan | Dampak | Solusi (Konfigurasi Selanjutnya) |
|-------------|--------|----------------------------------|
| 1 VM, semua komponen bercampur | Resource sharing → bottleneck | Pisahkan MongoDB ke VM terpisah |
| Tidak ada load balancer | Tidak bisa scale horizontal | Tambah Nginx upstream + VM backend |
| WiredTiger cache 2 GB (shared VM) | Performa DB terbatas saat spike | Gunakan MongoDB dedicated VM |
| Gunicorn 8 workers (gthread) | Concurrency terbatas 16 slot | Coba `gevent` atau tambah workers |
| Tidak ada CDN | Latensi frontend tinggi | Tambah CDN atau statik hosting |

---

## 11. Diagram Arsitektur (Teks)

```
┌──────────────────────────────────────────────────────────────────┐
│                  DigitalOcean Droplet — $48/mo                    │
│        Ubuntu 24.04 LTS | 4 vCPU | 8 GB RAM | 160 GB SSD         │
│                                                                    │
│  ┌──────────────────── Docker Engine ──────────────────────────┐  │
│  │                                                              │  │
│  │  ┌─────────────┐      ┌──────────────────┐                  │  │
│  │  │   Nginx     │      │  Flask + Gunicorn │                  │  │
│  │  │  1.25-alpine│─────▶│  8 workers       │                  │  │
│  │  │  port: 80   │      │  2 threads/worker│                  │  │
│  │  │  ~20-50 MB  │      │  ~800 MB-1.5 GB │                  │  │
│  │  └─────────────┘      └────────┬─────────┘                  │  │
│  │         ▲                      │                              │  │
│  │         │                      ▼                              │  │
│  │     Internet            ┌─────────────┐                      │  │
│  │    (port 80)            │  MongoDB    │                      │  │
│  │                         │    7.0      │                      │  │
│  │                         │ cache 2 GB  │                      │  │
│  │                         │  ~2-3 GB   │                      │  │
│  │                         └─────────────┘                      │  │
│  │                                                              │  │
│  │            [Docker network: app_net 172.20.0.0/24]          │  │
│  └──────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 12. Tabel Biaya

| Komponen | Spesifikasi | Harga/bulan |
|----------|-------------|-------------|
| Droplet (Basic) | 4 vCPU, 8 GB RAM, 160 GB SSD | **$48.00** |
| Load Balancer | Tidak digunakan | $0 |
| VM Tambahan | Tidak ada | $0 |
| **Total** | | **$48.00 / bulan** |

> Dalam rupiah (kurs ~Rp16.000/USD): **≈ Rp 768.000 / bulan**  
> Masih di bawah budget maksimal **Rp 1.300.000 / bulan**

---
