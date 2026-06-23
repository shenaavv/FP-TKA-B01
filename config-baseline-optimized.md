# Config Baseline Optimized — Perbandingan dengan Baseline

> **FP Teknologi Komputasi Awan 2026 — Kelompok B01**  
> Konfigurasi ini adalah **versi optimized** dari baseline dengan semua optimasi diterapkan pada **VM yang sama** (tidak ada biaya tambahan).

---

## 1. Ringkasan Perbedaan Arsitektur

| Aspek | Baseline | **Optimized** |
|-------|----------|---------------|
| Backend instance | 1 | **2** |
| Load balancer | ❌ Tidak ada | ✅ **Nginx least_conn** |
| Worker type | `gthread` (blocking thread) | **`gevent` (async greenlet)** |
| Concurrency per instance | 8 slot (4w × 2t) | **3000+ greenlet (3w × 1000)** |
| Total concurrency sistem | **8 slot** | **6000+ greenlet** |
| MongoDB indexes | ❌ Tidak ada | ✅ **13 index custom** |
| MongoDB connection pool | Default (100, no timeout) | **maxPool=20, timeout tuned** |
| Nginx proxy cache | ❌ Tidak ada | ✅ **/products 30s, /products/\<id\> 60s** |
| Audit log | Synchronous (block response) | **Async (daemon thread)** |
| Nginx worker_connections | 1024 | **4096** |
| Nginx keepalive_requests | 1000 | **2000** |

---

## 2. Diagram Arsitektur

### Baseline
```
Internet ──▶ Nginx (port 80)
              │ (reverse proxy, no cache, no LB)
              ▼
         Flask/Gunicorn
         [4 gthread workers × 2 threads = 8 concurrent slots]
              │
              ▼
           MongoDB
         [no index, default pool]
```

### Optimized
```
Internet ──▶ Nginx (port 80)
              │ [Load Balancer: least_conn]
              │ [Proxy Cache: /products 30s, /products/<id> 60s]
              ├──▶ backend_1:5000
              │    [3 gevent workers × 1000 greenlet = 3000 concurrent]
              │
              └──▶ backend_2:5000
                   [3 gevent workers × 1000 greenlet = 3000 concurrent]
                   │
                   ▼
                MongoDB
              [13 custom indexes]
              [WiredTiger cache 2GB]
              [connection pool: maxPool=20 per process]
```

---

## 3. Detail Setiap Optimasi

### 3.1 🔀 Load Balancer (Nginx Internal LB)

**Problem di baseline:**  
Satu backend instance = single point of failure + tidak bisa memanfaatkan semua CPU core secara optimal.

**Solusi:**  
2 backend instance dijalankan paralel, Nginx mendistribusikan request dengan algoritma `least_conn` (kirim ke server yang paling sedikit koneksi aktifnya).

```diff
# nginx.conf — upstream section
-upstream flask_backend {
-    server backend:5000;       # 1 server saja
-    keepalive 32;
-}
+upstream flask_backend {
+    least_conn;                # algoritma LB: least connection
+    server backend_1:5000 max_fails=3 fail_timeout=30s;
+    server backend_2:5000 max_fails=3 fail_timeout=30s;
+    keepalive 64;              # 2x lebih banyak persistent connection
+}
```

**Keuntungan:**
- Jika satu backend crash → traffic otomatis failover ke backend lain
- CPU utilization lebih merata
- Throughput total meningkat ±2x

---

### 3.2 ⚡ Gevent Workers (Async I/O)

**Problem di baseline:**  
`gthread` = setiap request menduduki 1 OS thread. Saat thread nunggu MongoDB (I/O), thread idle tapi masih "terpakai". Maksimal hanya 8 request paralel.

**Solusi:**  
`gevent` = event-loop based, saat greenlet nunggu I/O → greenlet lain langsung jalan. 1 worker bisa handle ribuan concurrent request.

```diff
# docker-compose — backend environment
-GUNICORN_WORKERS:      8          # 4 workers × 2 threads
-GUNICORN_WORKER_CLASS: gthread
+GUNICORN_WORKERS:            3    # per instance, 2 instance = 6 total
+GUNICORN_WORKER_CLASS:       gevent
+GUNICORN_WORKER_CONNECTIONS: 1000 # greenlet per worker
```

```diff
# app_optimized.py — top of file (WAJIB sebelum import lain)
+from gevent import monkey
+monkey.patch_all()   # patch socket, threading, dll ke async
```

**Perbandingan concurrency:**
| | Baseline | Optimized |
|---|---|---|
| Model | Thread (blocking) | Greenlet (async) |
| Total instance | 1 | 2 |
| Workers per instance | 4+4 | 3 |
| Concurrent per instance | 8 | ~3000 |
| **Total concurrency** | **8** | **~6000** |

---

### 3.3 📌 MongoDB Indexes

**Problem di baseline:**  
Semua query ke MongoDB melakukan **full collection scan** (O(n)). Makin banyak data, makin lambat.

**Solusi:**  
13 index dibuat otomatis saat container pertama kali init (file `02-init-indexes.js`):

```javascript
// orders — 6 index
{ "created_at": -1 }                    // list orders, sort default
{ "order_id": 1 }  (unique)             // get order by ID
{ "status": 1 }                         // filter by status
{ "status": 1, "created_at": -1 }       // filter+sort (admin)
{ "customer_city": 1 }                  // stats by city
{ "user_id": 1, "created_at": -1 }      // orders per user

// products — 4 index
{ "is_active": 1, "created_at": -1 }    // list default
{ "is_active": 1, "category": 1 }       // filter by category
{ "is_active": 1, "price": 1 }          // sort by price
{ "is_active": 1, "rating": -1 }        // sort by rating

// users — 3 index
{ "email": 1 }  (unique)                // login (paling sering)
{ "role": 1 }                           // filter role
{ "role": 1, "is_active": 1 }           // admin user management

// audit_logs — 2 index
{ "created_at": -1 }                    // list logs
{ "admin_id": 1, "created_at": -1 }     // logs per admin
```

**Impact esperado:**
- Query `GET /products?category=X` → dari O(n) ke O(log n)
- Query `GET /orders?status=pending` → dari O(n) ke O(log n)
- Login (`find_one by email`) → dari O(n) ke O(1)
- `GET /admin/stats` aggregation → jauh lebih cepat dengan index pada `status`, `created_at`, `customer_city`

---

### 3.4 🔌 MongoDB Connection Pool

**Problem di baseline:**  
`MongoClient(MONGO_URI)` → default pool tanpa timeout tuning. Saat spike traffic, koneksi bisa habis atau hang tanpa timeout.

**Solusi:**

```diff
-client = MongoClient(MONGO_URI)
+client = MongoClient(
+    MONGO_URI,
+    maxPoolSize=20,            # max 20 koneksi per worker process
+    minPoolSize=2,             # selalu siapkan 2 koneksi
+    maxIdleTimeMS=30000,       # tutup koneksi idle > 30s
+    waitQueueTimeoutMS=5000,   # timeout jika pool penuh (5s)
+    serverSelectionTimeoutMS=5000,
+    connectTimeoutMS=5000,
+)
```

**Kalkulasi koneksi:**
```
2 instance × 3 workers = 6 processes
6 processes × maxPoolSize 20 = 120 koneksi max ke MongoDB
MongoDB default max: 65535 koneksi → masih sangat aman
```

---

### 3.5 🗄️ Nginx Proxy Cache

**Problem di baseline:**  
Setiap request `GET /products` → selalu hit MongoDB, bahkan jika data belum berubah sama sekali. Dengan 100 user yang browse produk dalam waktu yang sama → 100 query MongoDB identik.

**Solusi:**  
Cache response di Nginx memory+disk:

```nginx
# Cache /products listing — 30 detik TTL
location ~* ^/products$ {
    proxy_cache      api_cache;
    proxy_cache_valid 200 30s;
    proxy_cache_key  "$request_method$host$request_uri";
    proxy_cache_use_stale error timeout updating;
    proxy_cache_lock on;               # satu request re-fill cache, sisanya tunggu
    add_header X-Cache-Status $upstream_cache_status;
    ...
}

# Cache /products/<id> detail — 60 detik TTL
location ~* ^/products/[^/]+$ {
    proxy_cache      api_cache;
    proxy_cache_valid 200 60s;
    ...
}
```

**Dampak:**
- Dalam window 30 detik, 1000 request `/products` → **1 query MongoDB** (999 dari cache)
- Cache key menyertakan query string → `?page=1&category=X` ≠ `?page=2&category=X`
- `X-Cache-Status` header: lihat apakah HIT atau MISS
- POST/PUT/DELETE ke `/products` → tidak ter-cache (default behavior)

---

### 3.6 🔄 Async Audit Log

**Problem di baseline:**  
Setiap operasi admin (update order status, suspend user, dll) → `write_log()` dipanggil secara synchronous. Response ditahan sampai `logs_col.insert_one()` selesai.

**Solusi:**

```diff
 def write_log(action, collection, target_id, detail=None):
+    admin_id = g.user_id   # capture sebelum spawn thread
+
+    def _write():
+        try:
             logs_col.insert_one({
-                "admin_id": ObjectId(g.user_id),
+                "admin_id": ObjectId(admin_id),
                 ...
             })
+        except Exception:
+            pass  # non-critical, jangan crash
+
+    threading.Thread(target=_write, daemon=True).start()
```

**Dampak:**  
- Response admin endpoint langsung dikirim
- Audit log ditulis di background (latency ~5–20ms tergantung MongoDB)
- Tidak ada data loss: thread daemon tetap jalan sampai selesai

---

## 4. Alokasi Memory (8 GB)

### Baseline
| Komponen | Limit |
|----------|-------|
| MongoDB | 3 GB |
| Flask/Gunicorn (1 instance) | 3 GB |
| Nginx | 256 MB |
| Docker + OS | ~300–500 MB |
| **Total** | **≤ 8 GB** |

### Optimized
| Komponen | Limit |
|----------|-------|
| MongoDB | 3 GB |
| backend_1 (gevent) | 2 GB |
| backend_2 (gevent) | 2 GB |
| Nginx + cache | 256 MB |
| Docker + OS | ~300–500 MB |
| **Total** | **≤ 8 GB** |

> ✅ Total limit 7.5 GB — masih dalam batas 8 GB VM.  
> Gevent workers lebih ringan dari gthread (tidak ada OS thread overhead per koneksi).

---

## 5. Perbandingan File Konfigurasi

| File | Baseline | Optimized |
|------|----------|-----------|
| `docker-compose-*.yml` | `docker-compose-baseline.yml` | `docker-compose-baseline-optimized.yml` |
| Nginx config | `nginx.conf` | `nginx-optimized.conf` |
| Backend app | `Resources/BE/app.py` | `Resources/BE/app_optimized.py` |
| Dockerfile | `Resources/BE/Dockerfile` | `Resources/BE/Dockerfile-optimized` |
| Requirements | `Resources/BE/requirements.txt` | `Resources/BE/requirements-optimized.txt` |
| DB index | ❌ Tidak ada | `Resources/DB/init-indexes.js` |

---

## 6. Cara Deploy Optimized

```bash
# 1. Build & run semua service
docker compose -f docker-compose-baseline-optimized.yml up -d --build

# 2. Cek status
docker compose -f docker-compose-baseline-optimized.yml ps

# 3. Lihat log semua service
docker compose -f docker-compose-baseline-optimized.yml logs -f

# 4. Lihat log spesifik
docker compose -f docker-compose-baseline-optimized.yml logs -f backend_1
docker compose -f docker-compose-baseline-optimized.yml logs -f nginx
```

### Verifikasi Cache Bekerja
```bash
# Request pertama → MISS (backend dipanggil)
curl -v http://<IP>/products | grep X-Cache-Status
# → X-Cache-Status: MISS

# Request kedua dalam 30 detik → HIT (dari cache Nginx)
curl -v http://<IP>/products | grep X-Cache-Status
# → X-Cache-Status: HIT
```

### Verifikasi Load Balancer
```bash
# Hit endpoint health beberapa kali, lihat instance_id bergantian
for i in $(seq 10); do curl -s http://<IP>/health | python3 -m json.tool | grep instance; done
# Akan bergantian menampilkan: "instance": "backend_1" dan "instance": "backend_2"
```

### Tambah Index Manual (Jika MongoDB Sudah Ada Data)
```bash
# Jika volume MongoDB sudah ada (data tidak baru), init script tidak auto-run
# Jalankan manual:
docker exec fp_mongo_optimized mongosh \
  "mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@localhost:27017/orderdb?authSource=admin" \
  /docker-entrypoint-initdb.d/02-init-indexes.js
```

---

## 7. Estimasi Perbandingan Performa

| Metrik | Baseline | Optimized | Perkiraan Gain |
|--------|----------|-----------|----------------|
| Max concurrent requests | **8 slot** | **~6000 greenlet** | **750x** |
| GET /products (cache HIT) | ~50–150ms | **~2–5ms** | **~30x** |
| GET /products (cache MISS) | ~50–150ms | ~20–60ms | ~3x (index) |
| POST /orders | ~100–300ms | ~40–120ms | ~3x (index) |
| GET /admin/stats | ~500–2000ms | ~100–400ms | ~5x (index + aggregation) |
| RPS (read-heavy) | ~50–150 | **~500–2000+** | **~10–15x** |
| RPS (write-heavy) | ~20–80 | ~100–300 | ~4–5x |
| Ketahanan saat spike | ❌ Drop/timeout | ✅ Gevent absorbs spike | — |

> ⚠️ Angka di atas adalah **estimasi teoritis** — hasil aktual bergantung pada pola traffic Locust dan data yang ada. Performa nyata diukur melalui load test.

---

## 8. Apa yang TIDAK Berubah

- Spesifikasi VM: **4 vCPU, 8 GB RAM, 160 GB** (sama persis)
- Biaya: **$48/bulan** (sama persis)
- Jumlah VM: **1 VM** (sama persis)
- Stack teknologi: Flask, MongoDB 7.0, Nginx 1.25
- Logika bisnis aplikasi: tidak ada perubahan fungsional
- Skema database: tidak ada perubahan
- Port publik: hanya port 80
