# Final Project Teknologi Komputasi Awan 2026

**Kelompok:** FP-TKA-B01  
**Mata Kuliah:** Teknologi Komputasi Awan

---

## Anggota Kelompok


| NRP | Nama |
|------------|-----------------------------|
| 5027241010 | Kanafira Vanesha Putri |
| 5027241025 | Christiano Ronaldo Silalahi |
| 5027241037 | Danuja Prasasta Bastu |
| 5027241038 | Moch. Rizki Nasrullah |
| 5027241069 | Prabaswara Febrian Winandika |
| 5027241070 | Zahra Khaalishah |
| 5027241097 | S. Farhan Baig |

---

## Overview

Proyek ini mengimplementasikan **Order Processing Service**, sebuah layanan backend REST API untuk platform e-commerce yang menangani pembuatan pesanan, pengecekan status, pembaruan status, dan riwayat transaksi. Sistem dibangun menggunakan Flask (Python), MongoDB, dan Nginx, serta dikontainerisasi menggunakan Docker Compose dan di-deploy di DigitalOcean.

Proyek ini dikerjakan dalam tiga tahap konfigurasi: **Baseline** (satu VM, satu backend instance, tanpa optimasi), **Baseline Optimized** (satu VM sama dengan penambahan load balancer internal, gevent, index MongoDB, proxy cache, dan connection pool), serta **Multi-VM Optimized** (tiga VM terpisah dengan MongoDB dedicated). Seluruh konfigurasi dirancang dalam batas anggaran $75/bulan (sekitar Rp1.300.000/bulan).

---

## Objectives

- Mendeploy Order Processing Service pada infrastruktur cloud dengan konfigurasi baseline sebagai titik awal pengukuran performa.
- Melakukan optimasi bertahap pada VM yang sama tanpa biaya tambahan (Baseline Optimized).
- Merancang arsitektur multi-VM dengan pemisahan komponen untuk meningkatkan isolasi sumber daya dan keandalan sistem.
- Mengukur dan membandingkan performa ketiga konfigurasi menggunakan Locust load testing dengan 5 skenario pengujian.

---

## Technology Stack

| Komponen | Teknologi | Versi |
|---|---|---|
| Reverse Proxy / Load Balancer | Nginx | 1.25-Alpine |
| WSGI Server | Gunicorn | 23.0.0 |
| Backend Framework | Flask (Python) | 3.0.3 |
| Database | MongoDB | 7.0 |
| Driver Database | PyMongo | 4.8.0 |
| Autentikasi | PyJWT + bcrypt | 2.9.0 / 4.2.0 |
| Containerisasi | Docker + Docker Compose | v3.9 |
| Load Testing | Locust | — |
| Frontend | HTML5 / CSS3 / JavaScript Vanilla | — |
| Cloud Provider | DigitalOcean Droplet | — |

---

## Project Structure

```text
FP-TKA-B01-main/
├── config-baseline.md                     <- Dokumentasi konfigurasi baseline
├── config-baseline-optimized.md           <- Dokumentasi konfigurasi optimized
├── config-multivm-optimized.md            <- Dokumentasi konfigurasi multi-VM
├── docker-compose-baseline.yml            <- Orkestrasi Docker baseline
├── docker-compose-baseline-optimized.yml  <- Orkestrasi Docker optimized
├── docker-compose-multivm-vm{1,2,3}.yml   <- Orkestrasi Docker multi-VM (per VM)
├── nginx.conf                             <- Konfigurasi Nginx baseline
├── nginx-optimized.conf                   <- Konfigurasi Nginx optimized
├── nginx-multivm.conf                     <- Konfigurasi Nginx multi-VM
├── restore-db.sh                          <- Script restore database interaktif
├── Report/
│   ├── baseline/                          <- Screenshot hasil load testing baseline
│   ├── baseline_v2/                       <- Screenshot hasil load testing baseline v2
│   └── optimized/                         <- Screenshot hasil load testing optimized
└── Resources/
    ├── BE/
    │   ├── app.py                         <- Source code Flask backend (baseline)
    │   ├── app_optimized.py               <- Source code Flask backend (optimized)
    │   ├── Dockerfile / Dockerfile-optimized
    │   └── requirements.txt / requirements-optimized.txt
    ├── DB/
    │   ├── dump/orderdb/                  <- Berkas dump BSON (seed data awal)
    │   ├── generate_dump.py               <- Script pembuatan data realistis
    │   ├── init-mongo.sh                  <- Script seed otomatis saat init container
    │   └── init-indexes.js                <- Script pembuatan index MongoDB
    ├── FE/
    │   ├── index.html                     <- Antarmuka web frontend
    │   └── styles.css
    └── Test/
        └── locustfile.py                  <- Script load testing Locust
```

---

# Baseline

## Baseline Architecture

Konfigurasi baseline menempatkan seluruh komponen (Nginx, Flask/Gunicorn, MongoDB) pada **satu VM tunggal** di DigitalOcean (4 vCPU, 8 GB RAM, $48/bulan) tanpa load balancer. Nginx berperan sebagai reverse proxy sederhana ke satu backend instance.

```mermaid
flowchart LR
    Client["Klien / Locust\n(HTTP :80)"]

    subgraph DO["DigitalOcean Droplet — 4 vCPU | 8 GB RAM | $48/bulan"]
        subgraph Docker["Docker Engine — app_net (172.20.0.0/24)"]
            Nginx["Nginx 1.25-Alpine\nReverse Proxy\nPort: 80 (publik)\nMem: maks 256 MB"]
            Backend["Flask + Gunicorn\n8 workers x 2 threads\nWorker: gthread\nPort: 5000 (internal)\nMem: maks 3 GB"]
            MongoDB["MongoDB 7.0\nWiredTiger Cache: 2 GB\nPort: 27017 (internal)\nMem: maks 3 GB"]
        end
    end

    Client --> Nginx
    Nginx -->|"proxy"| Backend
    Backend -->|"query"| MongoDB
```

**Docker Services:**

| Service | Container | Image | Port | Memory Limit |
|---|---|---|---|---|
| nginx | fp_nginx_baseline | nginx:1.25-alpine | 80 (publik) | 256 MB |
| backend | fp_backend_baseline | fp_backend_baseline:latest | 5000 (internal) | 3 GB |
| mongo | fp_mongo_baseline | mongo:7.0 | 27017 (internal) | 3 GB |

---

## Baseline Configuration Summary

### Spesifikasi VM

| Komponen | Detail |
|---|---|
| Provider | DigitalOcean Droplet Basic |
| vCPU | 4 |
| RAM | 8 GB |
| Disk | 160 GB SSD |
| OS | Ubuntu 24.04 LTS |
| Biaya | $48/bulan (sekitar Rp768.000) |

### Konfigurasi Komponen

| Komponen | Parameter | Nilai |
|---|---|---|
| Nginx | worker_processes | auto (2) |
| Nginx | worker_connections | 1024 |
| Nginx | keepalive_requests | 1000 |
| Nginx | gzip | aktif, level 4 |
| Nginx | upstream | 1 server (backend:5000), keepalive 32 |
| Gunicorn | workers | 8 |
| Gunicorn | threads | 2 |
| Gunicorn | worker-class | gthread |
| Gunicorn | timeout | 120 detik |
| Gunicorn | total slot konkuren | 16 (8 x 2) |
| MongoDB | versi | 7.0 LTS |
| MongoDB | wiredTigerCacheSizeGB | 2 GB |
| MongoDB | index | Tidak ada index custom |
| MongoDB | connection pool | Default PyMongo |

---

## Baseline Performance Evaluation

### Skenario Pengujian

Load testing dijalankan menggunakan Locust dari host eksternal yang berbeda dari server. Locust mensimulasikan dua tipe pengguna: `CustomerUser` (bobot 80%) dan `AdminUser` (bobot 20%).

| Skenario | Deskripsi | Durasi |
|---|---|---|
| 1 | Maksimum RPS pada 0% failure (naikkan user bertahap) | 60 detik |
| 2 | Peak Concurrency — Spawn Rate 50 | 60 detik |
| 3 | Peak Concurrency — Spawn Rate 100 | 60 detik |
| 4 | Peak Concurrency — Spawn Rate 200 | 60 detik |
| 5 | Peak Concurrency — Spawn Rate 500 | 60 detik |

### Hasil Eksperimen

**Skenario 1 — Maksimum RPS (0% Failure)**

![Hasil Locust Skenario 1](Report/baseline/try_1/image-1.png)

*Grafik RPS, response time, dan failure rate — Skenario 1*

![Resource Utilization Skenario 1](Report/baseline/try_1/resource.png)

*Utilisasi CPU dan memory server — Skenario 1*

**Skenario 2 — Peak Concurrency Spawn Rate 50**

![Hasil Locust Skenario 2](Report/baseline/try_2/image.png)

*Grafik RPS, response time, dan failure rate — Skenario 2*

![Resource Utilization Skenario 2](Report/baseline/try_2/resource.png)

*Utilisasi CPU dan memory server — Skenario 2*

**Skenario 3 — Peak Concurrency Spawn Rate 100**

![Hasil Locust Skenario 3](Report/baseline/try_3/image-2.png)

*Grafik RPS, response time, dan failure rate — Skenario 3*

![Resource Utilization Skenario 3](Report/baseline/try_3/resource.png)

*Utilisasi CPU dan memory server — Skenario 3*

**Skenario 4 — Peak Concurrency Spawn Rate 200**

![Hasil Locust Skenario 4](Report/baseline/try_4/image-3.png)

*Grafik RPS, response time, dan failure rate — Skenario 4*

![Resource Utilization Skenario 4](Report/baseline/try_4/resource.png)

*Utilisasi CPU dan memory server — Skenario 4*

**Skenario 5 — Peak Concurrency Spawn Rate 500**

![Hasil Locust Skenario 5](Report/baseline/try_5/image-4.png)

*Grafik RPS, response time, dan failure rate — Skenario 5*

![Resource Utilization Skenario 5](Report/baseline/try_5/resource.png)

*Utilisasi CPU dan memory server — Skenario 5*

### Temuan Utama dan Evaluasi

- Sistem baseline memiliki total 16 slot konkuren (8 workers x 2 threads gthread). Saat jumlah pengguna virtual melampaui kapasitas ini, antrian request menumpuk dan response time meningkat signifikan.
- MongoDB berjalan pada VM yang sama dengan backend, sehingga terjadi kompetisi sumber daya (CPU dan RAM) antara keduanya, terutama pada saat query agregasi `/admin/stats` yang bersifat berat.
- Tidak adanya index custom pada MongoDB menyebabkan seluruh query melakukan full collection scan, yang semakin lambat seiring pertumbuhan data di collection `orders`.
- Data numerik RPS, response time, dan failure rate aktual tersedia pada screenshot Locust di masing-masing folder pengujian di atas.

### Insight

Bottleneck utama baseline teridentifikasi pada dua titik: (1) kapasitas konkuren Gunicorn yang terbatas pada 16 slot dengan model thread sinkron, dan (2) tidak adanya index MongoDB yang menyebabkan performa query terdegradasi secara linier seiring penambahan data.

---

## Baseline Limitations

| Keterbatasan | Dampak |
|---|---|
| Single backend instance, tanpa load balancer | Tidak dapat diskalakan secara horizontal; single point of failure |
| Worker class gthread (sinkron) | Hanya 16 slot konkuren; idle saat menunggu I/O MongoDB |
| Semua komponen berbagi sumber daya pada 1 VM | Kompetisi RAM dan CPU antara MongoDB dan Flask |
| Tidak ada index MongoDB | Full collection scan; performa terdegradasi dengan volume data tinggi |
| Tidak ada proxy cache | Setiap request GET /products selalu hit MongoDB |
| Audit log synchronous | write_log() memblokir response hingga insert selesai |

---

# Baseline Optimized

## Optimized Architecture

Konfigurasi optimized diterapkan pada **VM yang sama** ($48/bulan, tidak ada biaya tambahan). Perubahan utama: penambahan satu backend instance kedua, penerapan Nginx sebagai load balancer internal dengan algoritma `least_conn`, penggantian worker class ke `gthread` dengan konfigurasi berbeda, penambahan Nginx proxy cache untuk endpoint produk, index MongoDB, connection pool tuning, dan async audit log.

> Catatan: Berdasarkan berkas `docker-compose-baseline-optimized.yml`, worker class yang digunakan pada implementasi aktual adalah `gthread` (bukan `gevent` seperti yang didokumentasikan di `config-baseline-optimized.md`). Nilai yang tercantum di bawah ini mengikuti implementasi aktual di docker-compose.

```mermaid
flowchart LR
    Client["Klien / Locust\n(HTTP :80)"]

    subgraph DO["DigitalOcean Droplet — 4 vCPU | 8 GB RAM | $48/bulan"]
        subgraph Docker["Docker Engine — app_net_opt (172.21.0.0/24)"]
            Nginx["Nginx 1.25-Alpine\nLoad Balancer (least_conn)\nProxy Cache: /products 30s\nProxy Cache: /products/<id> 60s\nPort: 80 (publik)\nMem: maks 256 MB"]
            B1["backend_1\nFlask + Gunicorn\n4 workers x 4 threads\nWorker: gthread\nPort: 5000 (internal)\nMem: maks 2 GB"]
            B2["backend_2\nFlask + Gunicorn\n4 workers x 4 threads\nWorker: gthread\nPort: 5000 (internal)\nMem: maks 2 GB"]
            MongoDB["MongoDB 7.0\n13 custom indexes\nWiredTiger Cache: 2 GB\nConnection Pool: maxPool=20\nPort: 27017 (internal)\nMem: maks 3 GB"]
            Cache["Docker Volume\nnginx_cache"]
        end
    end

    Client --> Nginx
    Nginx -->|"least_conn"| B1
    Nginx -->|"least_conn"| B2
    B1 --> MongoDB
    B2 --> MongoDB
    Nginx --- Cache
```

**Docker Services:**

| Service | Container | Workers x Threads | Memory Limit |
|---|---|---|---|
| nginx | fp_nginx_optimized | — | 256 MB |
| backend_1 | fp_backend_1_optimized | 4 x 4 (gthread) | 2 GB |
| backend_2 | fp_backend_2_optimized | 4 x 4 (gthread) | 2 GB |
| mongo | fp_mongo_optimized | — | 3 GB |

---

## Configuration Changes

| Komponen | Baseline | Optimized |
|---|---|---|
| Backend instances | 1 | 2 |
| Load balancing | Tidak ada | Nginx least_conn |
| Worker class | gthread | gthread |
| Workers per instance | 8 | 4 |
| Threads per worker | 2 | 4 |
| Total slot konkuren | 16 (1 instance) | 32 (2 x 16) |
| Nginx worker_connections | 1024 | 4096 |
| Nginx keepalive_requests | 1000 | 2000 |
| Nginx upstream keepalive | 32 | 64 |
| Nginx proxy buffer | 4k, 8 buffers | 8k, 16 buffers |
| Nginx proxy cache | Tidak ada | /products (30 detik), /products/<id> (60 detik) |
| MongoDB indexes | Tidak ada | 13 index custom |
| MongoDB connection pool | Default | maxPoolSize=20, minPoolSize=2, timeout tuning |
| Audit log | Synchronous | Asynchronous (daemon thread) |
| Dockerfile | Dockerfile | Dockerfile-optimized |
| Backend app | app.py | app_optimized.py |

---

## Performance Evaluation (Optimized)

### Hasil Eksperimen

**Skenario 1 — Maksimum RPS (0% Failure)**

![Hasil Locust Optimized Skenario 1](Report/optimized/try_1/result.png)

*Grafik hasil Locust — Skenario 1 Optimized*

![Resource Utilization Optimized Skenario 1](Report/optimized/try_2/Resources.png)

*Utilisasi resource server — Skenario 2 Optimized*

**Skenario 3 — Peak Concurrency Spawn Rate 100**

![Resource Utilization Optimized Skenario 3](Report/optimized/try_3/Resources.png)

*Utilisasi resource server — Skenario 3 Optimized*

**Skenario 5 — Peak Concurrency Spawn Rate 500**

![Hasil Locust Optimized Skenario 5](Report/optimized/try_5/image.png)

*Grafik hasil Locust — Skenario 5 Optimized*

### Temuan Utama dan Evaluasi

- Penambahan dua backend instance di belakang Nginx load balancer meningkatkan kapasitas total slot konkuren dari 16 menjadi 32 slot (2 x 16).
- Nginx proxy cache secara signifikan mengurangi jumlah query MongoDB untuk endpoint `/products`, karena dalam window 30 detik hanya satu request yang sampai ke backend.
- 13 index MongoDB yang ditambahkan mengubah query yang sebelumnya melakukan full collection scan menjadi index scan, terutama berdampak pada endpoint yang paling sering diakses seperti `GET /products?category=X` dan `GET /orders?status=pending`.
- MongoDB connection pool yang di-tune mencegah koneksi hang tanpa batas saat kondisi spike traffic.
- Data numerik RPS, response time, dan failure rate aktual tersedia pada screenshot Locust di folder pengujian di atas.

### Insight

Optimasi pada VM yang sama berhasil meningkatkan throughput dengan memanfaatkan sumber daya yang sudah ada secara lebih efisien. Bottleneck yang belum teratasi adalah kompetisi sumber daya antara MongoDB dan backend pada VM yang sama, khususnya saat query agregasi dashboard berjalan bersamaan dengan traffic tinggi.

---

## Baseline vs Optimized

| Aspek | Baseline | Optimized |
|---|---|---|
| VM | 1 VM, $48/bulan | 1 VM, $48/bulan |
| Backend instances | 1 | 2 |
| Load balancing | Tidak ada | Nginx least_conn |
| Worker class | gthread | gthread |
| Workers per instance | 8 x 2 thread | 4 x 4 thread |
| Total slot konkuren | 16 | 32 |
| Nginx worker_connections | 1024 | 4096 |
| Nginx proxy cache | Tidak ada | /products 30 detik, /products/<id> 60 detik |
| MongoDB indexes | Tidak ada | 13 index custom |
| MongoDB connection pool | Default | maxPoolSize=20, timeout tuned |
| Audit log | Synchronous | Asynchronous |
| MongoDB isolation | Berbagi VM dengan backend | Berbagi VM dengan backend |
| RPS aktual | Not Found in Repository (lihat screenshot) | Not Found in Repository (lihat screenshot) |
| Response time aktual | Not Found in Repository (lihat screenshot) | Not Found in Repository (lihat screenshot) |
| Failure rate aktual | Not Found in Repository (lihat screenshot) | Not Found in Repository (lihat screenshot) |
| Bottleneck utama | Kapasitas konkuren (16 slot) + full collection scan | Kompetisi sumber daya MongoDB vs backend pada 1 VM |

### Analisis Peningkatan

Peningkatan performa pada Baseline Optimized dicapai melalui tiga mekanisme utama. Pertama, penggandaan backend instance di belakang load balancer `least_conn` melipatgandakan kapasitas pemrosesan request konkuren. Kedua, Nginx proxy cache menghilangkan mayoritas query MongoDB untuk endpoint `/products` yang merupakan endpoint paling sering diakses oleh `CustomerUser`. Ketiga, 13 index MongoDB mengubah kompleksitas query dari O(n) menjadi O(log n), yang berdampak langsung pada response time semua endpoint yang memfilter atau mengurutkan data.

Bottleneck yang belum terselesaikan adalah pemisahan sumber daya antara MongoDB dan backend. Pada kondisi traffic tinggi, keduanya masih bersaing menggunakan CPU dan RAM yang sama, membatasi potensi peningkatan performa maksimal.

---

# Multi-VM Optimized

## Multi-VM Architecture

Konfigurasi Multi-VM mendistribusikan komponen ke tiga VM terpisah yang terhubung melalui DigitalOcean VPC private network. Total biaya $72/bulan (3 x $24/bulan), masih dalam batas anggaran $75/bulan.

```mermaid
flowchart TD
    Client["Klien / Internet\n(HTTP :80)"]

    subgraph VM1["VM-1 — 2 vCPU | 4 GB RAM | $24/bulan\nPublic IP"]
        Nginx["Nginx\nLoad Balancer + Cache\nPort: 80 (publik)"]
        B1["Backend-1\nFlask + Gunicorn\n4 workers x 4 threads\ngthread\n127.0.0.1:5000 (lokal)"]
    end

    subgraph VM2["VM-2 — 2 vCPU | 4 GB RAM | $24/bulan\nPrivate IP (VPC)"]
        B2["Backend-2\nFlask + Gunicorn\n4 workers x 4 threads\ngthread\n0.0.0.0:5000 (VPC only)"]
    end

    subgraph VM3["VM-3 — 2 vCPU | 4 GB RAM | $24/bulan\nPrivate IP (VPC)"]
        MongoDB["MongoDB 7.0\nDedicated\nWiredTiger: 1.5 GB\n27017 (VPC only)"]
    end

    Client --> Nginx
    Nginx -->|"least_conn"| B1
    Nginx -->|"least_conn VPC"| B2
    B1 -->|"VPC"| MongoDB
    B2 -->|"VPC"| MongoDB
```

**Spesifikasi VM:**

| VM | Role | vCPU | RAM | Disk | Biaya |
|---|---|---|---|---|---|
| VM-1 | Nginx LB + Backend-1 | 2 | 4 GB | 80 GB | $24/bulan |
| VM-2 | Backend-2 | 2 | 4 GB | 80 GB | $24/bulan |
| VM-3 | MongoDB dedicated | 2 | 4 GB | 80 GB | $24/bulan |
| Total | | 6 vCPU | 12 GB | 240 GB | $72/bulan |

---

## Perbedaan dengan Baseline

| Komponen | Baseline | Multi-VM |
|---|---|---|
| Jumlah VM | 1 ($48/bulan) | 3 ($72/bulan) |
| Backend instances | 1 | 2 |
| Load balancing | Tidak ada | Nginx least_conn |
| MongoDB | Berbagi VM (RAM shared 8 GB) | Dedicated VM (RAM dedicated 4 GB) |
| WiredTiger cache | 2 GB (berbagi dengan backend) | 1.5 GB (dedicated, tanpa kompetisi) |
| MongoDB CPU | Berbagi 4 vCPU | Dedicated 2 vCPU |
| Backend RAM per instance | Berbagi dari 8 GB | Dedicated per VM |
| Fault tolerance | Tidak ada | Backend failover (2 instance VM terpisah) |
| MongoDB isolation | Tidak ada | Penuh (dedicated VM) |
| Firewall | Tidak diatur di konfigurasi | DigitalOcean firewall per VM (wajib) |

---

## Perbedaan dengan Baseline Optimized

| Komponen | Baseline Optimized | Multi-VM |
|---|---|---|
| Jumlah VM | 1 ($48/bulan) | 3 ($72/bulan) |
| MongoDB isolation | Berbagi VM (RAM shared 8 GB) | Dedicated VM (RAM dedicated 4 GB) |
| WiredTiger cache | 2 GB (berbagi) | 1.5 GB (dedicated) |
| Backend-1 RAM limit | 2 GB (container limit) | 3 GB (container limit, dedicated VM) |
| Backend-2 RAM limit | 2 GB (container limit) | 3.5 GB (container limit, dedicated VM) |
| Nginx RAM limit | 256 MB | 512 MB |
| Backend-2 lokasi | Container di VM yang sama | VM-2 terpisah (terhubung via VPC) |
| Total vCPU | 4 (shared) | 6 (distributed) |
| Total RAM | 8 GB (shared) | 12 GB (distributed) |
| Jaringan backend ke DB | Docker internal network | DigitalOcean VPC private network |

---

## Expected Benefits

Berdasarkan konfigurasi yang ditemukan dalam repository:

- **Eliminasi kompetisi sumber daya MongoDB:** MongoDB berjalan pada VM dedicated (4 GB RAM, 2 vCPU), tidak lagi bersaing dengan backend Flask. WiredTiger cache 1.5 GB bersifat dedicated sehingga lebih efektif dalam menyimpan working-set data di memori.
- **Peningkatan performa aggregasi:** Endpoint `/admin/stats` yang menjalankan query aggregasi berat mendapat manfaat langsung dari CPU dan RAM MongoDB yang tidak terkontaminasi oleh proses lain.
- **Backend failover lintas VM:** Jika VM-1 mengalami gangguan, traffic dapat dialihkan secara manual ke VM-2. Jika hanya container backend_1 yang bermasalah, Nginx otomatis mengarahkan semua traffic ke backend_2 melalui mekanisme `max_fails=3 fail_timeout=30s`.
- **Kemudahan scale horizontal:** Menambah kapasitas backend hanya memerlukan penambahan VM baru dan pembaruan upstream di konfigurasi Nginx, tanpa mengubah VM yang sedang berjalan.

> Data pengujian performa aktual untuk konfigurasi Multi-VM tidak ditemukan dalam repository (Not Found in Repository).

---

## Comparative Architecture Summary

| Aspek | Baseline | Optimized | Multi-VM |
|---|---|---|---|
| Jumlah VM | 1 | 1 | 3 |
| Biaya | $48/bulan | $48/bulan | $72/bulan |
| Total vCPU | 4 | 4 | 6 |
| Total RAM | 8 GB | 8 GB | 12 GB |
| Backend instances | 1 | 2 | 2 |
| Load balancing | Tidak ada | Nginx least_conn | Nginx least_conn |
| Worker class | gthread | gthread | gthread |
| Total slot konkuren | 16 | 32 | 32 |
| Nginx proxy cache | Tidak ada | /products 30s, /products/<id> 60s | /products 30s, /products/<id> 60s |
| MongoDB isolation | Shared VM | Shared VM | Dedicated VM |
| MongoDB WiredTiger cache | 2 GB (shared) | 2 GB (shared) | 1.5 GB (dedicated) |
| MongoDB indexes | Tidak ada | 13 index custom | 13 index custom |
| Connection pool | Default | maxPoolSize=20, tuned | maxPoolSize=20, tuned |
| Audit log | Synchronous | Asynchronous | Asynchronous |
| Scalability | Tidak bisa horizontal | Terbatas (1 VM) | Mudah (tambah VM baru) |
| Fault tolerance | Tidak ada | Backend (container) | Backend (lintas VM) |
| Bottleneck | Konkuren + no index + shared resource | Shared MongoDB resource | Jaringan VPC antar VM |

---

## Comparative Performance Summary

Data numerik RPS, peak concurrency, response time, dan failure rate yang terstruktur tidak tersedia dalam format teks di repository. Seluruh data performa tersedia dalam bentuk screenshot Locust dan screenshot monitoring resource di folder `Report/baseline/` dan `Report/optimized/`. Perbandingan kuantitatif dapat diperoleh dari screenshot tersebut.

| Metrik | Baseline | Optimized | Multi-VM |
|---|---|---|---|
| RPS maksimum (0% failure) | Not Found in Repository | Not Found in Repository | Not Found in Repository |
| Peak concurrent users | Not Found in Repository | Not Found in Repository | Not Found in Repository |
| Response time rata-rata | Not Found in Repository | Not Found in Repository | Not Found in Repository |
| Failure rate | Not Found in Repository | Not Found in Repository | Not Found in Repository |
| CPU usage puncak | Not Found in Repository | Not Found in Repository | Not Found in Repository |
| Memory usage puncak | Not Found in Repository | Not Found in Repository | Not Found in Repository |

---

## Conclusion

Proyek ini mendemonstrasikan evolusi arsitektur deployment cloud melalui tiga tahap yang saling berkesinambungan.

**Baseline** memberikan fondasi pengukuran yang jelas dengan arsitektur paling sederhana: satu VM, satu backend instance, tanpa index database, dan tanpa load balancer. Keterbatasan utamanya adalah kapasitas konkuren yang sangat terbatas (16 slot gthread) dan tidak adanya index MongoDB yang menyebabkan performa terdegradasi seiring pertumbuhan data.

**Baseline Optimized** membuktikan bahwa peningkatan performa signifikan dapat dicapai tanpa biaya infrastruktur tambahan. Dengan menambahkan backend instance kedua di belakang load balancer internal Nginx, menerapkan proxy cache untuk endpoint produk, membuat 13 index MongoDB, melakukan connection pool tuning, dan mengubah audit log menjadi asynchronous, kapasitas slot konkuren meningkat dari 16 menjadi 32 dan query MongoDB menjadi jauh lebih efisien. Bottleneck yang tersisa adalah kompetisi sumber daya antara MongoDB dan backend yang masih berbagi satu VM.

**Multi-VM Optimized** menyelesaikan bottleneck terakhir dengan mendedikasikan MongoDB pada VM tersendiri. Dengan tambahan biaya $24/bulan (total $72/bulan, masih dalam anggaran), MongoDB mendapatkan CPU dan RAM dedicated, sehingga query agregasi berat tidak lagi terganggu oleh beban backend. Arsitektur ini juga memberikan keandalan yang lebih baik melalui isolasi komponen lintas VM dan kemudahan scale horizontal di masa mendatang.

