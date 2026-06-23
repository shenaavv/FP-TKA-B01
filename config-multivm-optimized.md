# Config Multi-VM Optimized — 3 VM @ $24/mo

> **FP Teknologi Komputasi Awan 2026 — Kelompok B01**  
> Arsitektur 3 VM terpisah: dedicated MongoDB, 2 backend instance, Nginx load balancer.  
> Total biaya: **$72/bulan** (dalam budget $75).

---

## 1. Arsitektur

```
Internet (HTTP port 80)
         │
         ▼
┌────────────────────────────────────┐
│  VM-1  │  $24/mo — 2 vCPU, 4 GB   │  ← public IP
│                                    │
│  Nginx (LB + Cache + Reverse Proxy)│
│  ├── upstream backend_1 (lokal)    │
│  └── upstream backend_2 (VM2 VPC)  │
│                                    │
│  Backend-1 (Gunicorn gthread)      │
│  127.0.0.1:5000 (internal only)   │
└────────────┬───────────────────────┘
             │ DigitalOcean VPC (private network)
     ┌───────┴────────┐
     │                │
     ▼                ▼
┌──────────────┐  ┌─────────────────────┐
│  VM-2        │  │  VM-3               │
│  $24/mo      │  │  $24/mo             │
│  2 vCPU, 4GB │  │  2 vCPU, 4 GB      │
│              │  │                     │
│  Backend-2   │  │  MongoDB 7.0        │
│  0.0.0.0:5000│  │  WiredTiger 1.5 GB  │
│  (VPC only)  │  │  27017 (VPC only)   │
└──────────────┘  └─────────────────────┘
```

---

## 2. Spesifikasi Per VM

| VM | Role | vCPU | RAM | Disk | Harga |
|----|------|------|-----|------|-------|
| VM-1 | Nginx LB + Backend-1 | 2 | 4 GB | 80 GB | $24/mo |
| VM-2 | Backend-2 | 2 | 4 GB | 80 GB | $24/mo |
| VM-3 | MongoDB dedicated | 2 | 4 GB | 80 GB | $24/mo |
| **Total** | | **6 vCPU** | **12 GB** | **240 GB** | **$72/mo** |

---

## 3. File Config Per VM

| File | Dipakai di VM |
|------|--------------|
| `docker-compose-multivm-vm1.yml` | VM-1 (Nginx + Backend-1) |
| `docker-compose-multivm-vm2.yml` | VM-2 (Backend-2) |
| `docker-compose-multivm-vm3.yml` | VM-3 (MongoDB) |
| `nginx-multivm.conf` | VM-1 (sebagai nginx template) |
| `.env.multivm.example` | Semua VM (template, isi IP yang benar) |

---

## 4. Cara Deploy Step-by-Step

### Prasyarat di semua VM
```bash
# Install Docker
curl -fsSL https://get.docker.com | bash
systemctl enable docker && systemctl start docker

# Clone repo
git clone https://github.com/shenaavv/FP-TKA-B01.git
cd FP-TKA-B01
```

### Cari Private IP masing-masing VM
```bash
# Di DigitalOcean console → Droplet → Networks → Private IP
# ATAU di dalam VM:
ip addr show eth1 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
```

---

### STEP 1: Setup VM-3 (MongoDB) — deploy pertama

```bash
# 1. Buat .env di VM-3
cp .env.multivm.example .env
nano .env
# Isi: MONGO_INITDB_ROOT_USERNAME, MONGO_INITDB_ROOT_PASSWORD, MONGO_INITDB_DATABASE
# MONGO_URI dan VM2_PRIVATE_IP tidak diperlukan di VM-3

# 2. Jalankan MongoDB
docker compose -f docker-compose-multivm-vm3.yml up -d

# 3. Cek status dan tunggu healthy
docker compose -f docker-compose-multivm-vm3.yml ps
docker logs fp_mongo_multivm --tail 30

# 4. Verifikasi MongoDB bisa diakses
docker exec fp_mongo_multivm mongosh --quiet --eval "db.adminCommand('ping')"
```

### STEP 2: Setup VM-2 (Backend-2) — deploy kedua

```bash
# 1. Buat .env di VM-2
cp .env.multivm.example .env
nano .env
# Wajib diisi:
#   MONGO_URI=mongodb://admin:PASS@<VM3_PRIVATE_IP>:27017/orderdb?authSource=admin
# VM2_PRIVATE_IP tidak diperlukan di VM-2

# 2. Build dan jalankan Backend-2
docker compose -f docker-compose-multivm-vm2.yml up -d --build

# 3. Verifikasi backend berjalan
curl http://localhost:5000/health
# Expected: {"status": "ok", "instance": "backend_2", ...}
```

### STEP 3: Setup VM-1 (Nginx + Backend-1) — deploy terakhir

```bash
# 1. Buat .env di VM-1
cp .env.multivm.example .env
nano .env
# Wajib diisi:
#   MONGO_URI=mongodb://admin:PASS@<VM3_PRIVATE_IP>:27017/orderdb?authSource=admin
#   VM2_PRIVATE_IP=<private IP VM-2>

# 2. Build dan jalankan Backend-1 + Nginx
docker compose -f docker-compose-multivm-vm1.yml up -d --build

# 3. Verifikasi
curl http://localhost/health
curl http://localhost/nginx-health
```

---

## 5. DigitalOcean Firewall Rules

> ⚠️ **WAJIB dikonfigurasi** agar MongoDB dan Backend-2 tidak bisa diakses publik.

### VM-3 (MongoDB) — Firewall Rules
| Type | Protocol | Port | Source |
|------|----------|------|--------|
| Inbound | TCP | 22 | Your IP (SSH) |
| Inbound | TCP | 27017 | VM-1 private IP, VM-2 private IP |
| Outbound | All | All | All |

### VM-2 (Backend-2) — Firewall Rules
| Type | Protocol | Port | Source |
|------|----------|------|--------|
| Inbound | TCP | 22 | Your IP (SSH) |
| Inbound | TCP | 5000 | VM-1 private IP |
| Outbound | All | All | All |

### VM-1 (Nginx) — Firewall Rules
| Type | Protocol | Port | Source |
|------|----------|------|--------|
| Inbound | TCP | 22 | Your IP (SSH) |
| Inbound | TCP | 80 | All (0.0.0.0/0) |
| Outbound | All | All | All |

---

## 6. Verifikasi Setelah Deploy

### Cek Load Balancer bekerja
```bash
# Hit /health berulang, lihat instance bergantian antara backend_1 dan backend_2
for i in $(seq 10); do
  curl -s http://<VM1_PUBLIC_IP>/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['instance'])"
done
# Output bergantian: backend_1, backend_2, backend_1, backend_2, ...
```

### Cek Nginx Cache
```bash
# Request pertama → MISS
curl -sI http://<VM1_PUBLIC_IP>/products | grep X-Cache-Status
# → X-Cache-Status: MISS

# Request kedua dalam 30 detik → HIT
curl -sI http://<VM1_PUBLIC_IP>/products | grep X-Cache-Status
# → X-Cache-Status: HIT
```

### Cek MongoDB Indexes
```bash
# Di VM-3
docker exec fp_mongo_multivm mongosh \
  "mongodb://admin:TKAB01%402026@localhost:27017/orderdb?authSource=admin" \
  --quiet --eval "
    db.orders.getIndexes().forEach(i => print(i.name));
    db.products.getIndexes().forEach(i => print(i.name));
  "
```

### Restore Database (jika volume baru)
```bash
# Di VM-3 (atau dari VM yang bisa akses VM-3)
# Update CONTAINER_NAME di restore-db.sh ke fp_mongo_multivm
bash restore-db.sh
```

---

## 7. Perbandingan Arsitektur

| Metrik | Baseline (1 VM $48) | Optimized (1 VM $48) | **Multi-VM (3 VM $72)** |
|--------|---------------------|----------------------|------------------------|
| MongoDB RAM | shared ~4 GB | shared ~4 GB | **dedicated 4 GB** |
| WiredTiger cache | 2 GB (share) | 2 GB (share) | **1.5 GB (dedicated)** |
| MongoDB CPU | shared 4 vCPU | shared 4 vCPU | **dedicated 2 vCPU** |
| Backend instances | 1 | 2 | **2** |
| Backend RAM/instance | shared | 2 GB | **4 GB dedicated** |
| Concurrent slots | 32 | 32 | **2 × 16 = 32** |
| Fault tolerant | ❌ | ⚠️ Backend only | ✅ Backend failover |
| MongoDB isolation | ❌ | ❌ | ✅ No resource contention |
| Biaya | $48/mo | $48/mo | $72/mo |

---

## 8. Alokasi Memory Per VM

### VM-1 (4 GB)
| Komponen | Limit | Estimasi |
|----------|-------|----------|
| Backend-1 (Gunicorn) | 2 GB | ~400–800 MB |
| Nginx + cache | 512 MB | ~30–50 MB |
| Docker + OS | — | ~300–500 MB |
| **Tersisa** | | **~1.5–3 GB headroom** |

### VM-2 (4 GB)
| Komponen | Limit | Estimasi |
|----------|-------|----------|
| Backend-2 (Gunicorn) | 3.5 GB | ~400–800 MB |
| Docker + OS | — | ~300–500 MB |
| **Tersisa** | | **~2.5–3 GB headroom** |

### VM-3 (4 GB)
| Komponen | Limit | Estimasi |
|----------|-------|----------|
| MongoDB | 3.5 GB | ~1.5–3 GB |
| Docker + OS | — | ~300–500 MB |
| **WiredTiger cache** | **1.5 GB** | dedicated, tidak berkompetisi |

---

## 9. Keuntungan vs Single VM

1. **MongoDB tidak berebut RAM dengan Flask** → WiredTiger cache lebih efektif
2. **MongoDB CPU dedicated** → `/admin/stats` aggregation lebih cepat
3. **Backend failover** → jika VM-1 down, request bisa di-redirect ke VM-2 manual
4. **Scale horizontal mudah** → tinggal tambah VM-2 replika dan update nginx upstream
5. **Maintenance tanpa downtime** → update backend satu-satu tanpa mematikan seluruh sistem
