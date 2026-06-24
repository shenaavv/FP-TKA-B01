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

Proyek ini merupakan Final Project mata kuliah Teknologi Komputasi Awan 2026. Proyek mengimplementasikan sebuah **Order Processing Service**, yaitu layanan backend berbasis REST API yang menangani pemrosesan pesanan pada platform e-commerce.

Konteks permasalahan yang diselesaikan adalah sebagai berikut: sebuah perusahaan rintisan di bidang e-commerce membutuhkan layanan backend untuk menangani pembuatan pesanan, pengecekan status pesanan, pembaruan status, dan penelusuran riwayat transaksi. Layanan ini harus mampu menangani lonjakan traffic seperti pada kondisi flash sale atau promo, dengan batasan anggaran infrastruktur cloud sebesar maksimal Rp1.300.000 per bulan (setara sekitar 75 dolar AS).

Sistem ini terdiri dari tiga komponen utama yang berjalan dalam satu lingkungan Docker Compose: Nginx sebagai reverse proxy dan server berkas frontend statis, Flask melalui Gunicorn sebagai backend REST API, serta MongoDB sebagai basis data penyimpanan seluruh data transaksi, produk, dan pengguna. Seluruh komponen ini di-deploy pada satu virtual machine (VM) di DigitalOcean.

---

## Objectives

Tujuan implementasi baseline dalam proyek ini adalah:

- Mendeploy seluruh komponen sistem (backend Flask, database MongoDB, reverse proxy Nginx, dan frontend statis) pada satu VM tunggal di DigitalOcean sebagai titik awal pengukuran performa.
- Menetapkan konfigurasi dasar Gunicorn dengan 8 worker dan 2 thread per worker (total 16 slot konkuren) untuk melayani request secara paralel.
- Mengukur kemampuan maksimum sistem dalam kondisi tanpa optimasi skala keluar, tanpa load balancer, dan tanpa pemisahan komponen ke VM terpisah.
- Mendokumentasikan hasil load testing menggunakan Locust dengan 5 skenario pengujian yang mencakup pengukuran RPS (Requests Per Second) maksimum pada tingkat kegagalan 0%, serta pengujian peak concurrency pada berbagai spawn rate.
- Memberikan landasan perbandingan (baseline) sebelum dilakukan optimasi lebih lanjut seperti konfigurasi multi-VM atau penerapan load balancer.

---

## Repository Analysis Summary

Berdasarkan hasil analisis menyeluruh terhadap repository, berikut adalah ringkasan temuan:

| Aspek | Temuan |
|---|---|
| Bahasa Pemrograman Utama | Python 3.11 |
| Framework Backend | Flask 3.0.3 |
| WSGI Server | Gunicorn 23.0.0 |
| Database | MongoDB 7.0 |
| Reverse Proxy | Nginx 1.25 (Alpine) |
| Autentikasi | JWT (PyJWT 2.9.0) dengan bcrypt 4.2.0 |
| Containerisasi | Docker dan Docker Compose v3.9 |
| Frontend | HTML5, CSS3, JavaScript Vanilla (tidak menggunakan framework) |
| Arsitektur Sistem | Single-VM, all-in-one deployment |
| Strategi Deployment Baseline | Satu Droplet DigitalOcean (4 vCPU, 8 GB RAM) |
| Tool Load Testing | Locust |
| Manajemen Database | mongorestore untuk seed data awal |
| Modul Utama | app.py (Flask REST API), locustfile.py (load testing), generate_dump.py (pembuatan data) |

---

## System Architecture

### Komponen Sistem

**Input Layer**
Seluruh request masuk dari klien (browser atau Locust) melalui port 80 HTTP menuju container Nginx.

**Reverse Proxy Layer**
Nginx 1.25 (Alpine) berperan sebagai reverse proxy tunggal. Nginx melayani berkas frontend statis (index.html, styles.css) secara langsung dari direktori `/usr/share/nginx/html`. Apabila berkas statis tidak ditemukan, request diteruskan ke upstream Flask backend melalui internal Docker network. Nginx tidak berfungsi sebagai load balancer pada konfigurasi baseline ini.

**Application Layer**
Flask 3.0.3 dijalankan oleh Gunicorn 23.0.0 dengan tipe worker `gthread`, 8 worker process, dan 2 thread per worker, menghasilkan total 16 slot konkuren. Backend ini menangani seluruh logika bisnis: autentikasi pengguna, manajemen produk, pemrosesan pesanan, statistik admin, dan audit log.

**Database Layer**
MongoDB 7.0 menyimpan seluruh data dalam database bernama `orderdb`. MongoDB berjalan sebagai container terpisah dalam jaringan Docker internal dan tidak diekspos ke luar host. WiredTiger cache dikonfigurasi sebesar 2 GB dari total 8 GB RAM VM.

**Frontend Layer**
Frontend berupa halaman HTML5 statis dengan CSS3 dan JavaScript Vanilla. Halaman ini memungkinkan pengguna membuat pesanan baru, mengecek status pesanan, memperbarui status pesanan, dan melihat riwayat pesanan melalui pemanggilan Fetch API ke endpoint backend.

**Deployment Layer**
Seluruh komponen berjalan di dalam Docker Engine pada satu Droplet DigitalOcean (Ubuntu 24.04 LTS, 4 vCPU, 8 GB RAM, 160 GB SSD) dengan biaya $48 per bulan. Orkestrasi container dilakukan menggunakan Docker Compose dengan berkas `docker-compose-baseline.yml`.

### Diagram Arsitektur Sistem

```mermaid
flowchart TD
    Client["Klien / Browser / Locust\n(HTTP Port 80)"]

    subgraph DO["DigitalOcean Droplet — Ubuntu 24.04 LTS\n4 vCPU | 8 GB RAM | 160 GB SSD | $48/bulan"]
        subgraph Docker["Docker Engine"]
            subgraph appnet["Docker Network: app_net (172.20.0.0/24)"]
                Nginx["Nginx 1.25-Alpine\nReverse Proxy + Static Files\nPort: 80 (expose)\nMemory: maks 256 MB"]
                Backend["Flask 3.0.3 + Gunicorn 23.0.0\n8 Workers x 2 Threads = 16 slot\nWorker Class: gthread\nPort: 5000 (internal)\nMemory: maks 3 GB"]
                MongoDB["MongoDB 7.0\nDatabase: orderdb\nWiredTiger Cache: 2 GB\nPort: 27017 (internal)\nMemory: maks 3 GB"]
            end
        end
    end

    FE["Frontend Statis\n(index.html, styles.css)\nMount: Resources/FE/"]
    Volume["Docker Volume\nmongo_data\nmongo_config"]

    Client -->|"HTTP :80"| Nginx
    Nginx -->|"Static Files"| FE
    Nginx -->|"API Request\nHTTP :5000"| Backend
    Backend -->|"Query / Write\nPort 27017"| MongoDB
    MongoDB --- Volume
```

---

## Technology Stack

| Komponen | Teknologi | Versi | Tujuan |
|---|---|---|---|
| Reverse Proxy | Nginx | 1.25-Alpine | Meneruskan request HTTP ke backend dan melayani berkas statis frontend |
| WSGI Server | Gunicorn | 23.0.0 | Menjalankan aplikasi Flask secara multi-worker dan multi-thread |
| Backend Framework | Flask | 3.0.3 | REST API untuk pemrosesan pesanan, produk, pengguna, dan admin |
| Database | MongoDB | 7.0 | Penyimpanan data non-relasional (users, products, orders, audit_logs, sessions) |
| Runtime Backend | Python | 3.11 | Bahasa pemrograman utama aplikasi backend |
| Driver MongoDB | PyMongo | 4.8.0 | Koneksi Python ke MongoDB |
| Autentikasi | PyJWT | 2.9.0 | Pembuatan dan validasi token JWT |
| Enkripsi Kata Sandi | bcrypt | 4.2.0 | Hashing password pengguna |
| Containerisasi | Docker + Docker Compose | v3.9 | Orkestrasi seluruh service dalam container terisolasi |
| Load Testing | Locust | (terinstall di host penguji) | Simulasi beban traffic dan pengukuran performa |
| Frontend | HTML5 / CSS3 / JavaScript | Vanilla | Antarmuka web sederhana untuk interaksi pengguna |
| Pembuatan Data Uji | Faker | (library Python) | Pembuatan data realistis berbahasa Indonesia untuk seeding database |
| Serialisasi Data | BSON | (PyMongo) | Format penyimpanan dan dump data MongoDB |
| OS (VM) | Ubuntu | 24.04 LTS | Sistem operasi virtual machine di DigitalOcean |
| Cloud Provider | DigitalOcean | Droplet Basic | Infrastruktur cloud tempat deployment baseline |

---

## Project Structure

```text
FP-TKA-B01-main/
├── README.md                              <- Dokumentasi ringkas kelompok
├── Soal_FP.md                             <- Spesifikasi dan rubrik penilaian FP
├── config-baseline.md                     <- Dokumentasi konfigurasi baseline lengkap
├── config-baseline-optimized.md           <- Dokumentasi konfigurasi versi optimized
├── config-multivm-optimized.md            <- Dokumentasi konfigurasi multi-VM
├── docker-compose-baseline.yml            <- Orkestrasi Docker untuk konfigurasi baseline
├── docker-compose-baseline-optimized.yml  <- Orkestrasi Docker untuk versi optimized
├── docker-compose-multivm-vm1.yml         <- Orkestrasi Docker VM1 (multi-VM)
├── docker-compose-multivm-vm2.yml         <- Orkestrasi Docker VM2 (multi-VM)
├── docker-compose-multivm-vm3.yml         <- Orkestrasi Docker VM3 (multi-VM)
├── nginx.conf                             <- Konfigurasi Nginx untuk baseline
├── nginx-optimized.conf                   <- Konfigurasi Nginx untuk versi optimized
├── nginx-multivm.conf                     <- Konfigurasi Nginx untuk multi-VM
├── restore-db.sh                          <- Script interaktif untuk restore database
├── scratch.py                             <- Script pengujian koneksi MongoDB
├── Report/
│   ├── baseline/                          <- Laporan dan hasil load testing baseline
│   │   ├── hasil_pengujian.md             <- Catatan skenario pengujian baseline
│   │   ├── try_1/                         <- Hasil skenario 1 (gambar Locust + resource)
│   │   ├── try_2/                         <- Hasil skenario 2
│   │   ├── try_3/                         <- Hasil skenario 3
│   │   ├── try_4/                         <- Hasil skenario 4
│   │   └── try_5/                         <- Hasil skenario 5
│   ├── baseline_optimized/                <- Laporan konfigurasi baseline optimized
│   └── baseline_v2/                       <- Laporan hasil pengujian versi v2
└── Resources/
    ├── BE/
    │   ├── Dockerfile                     <- Dockerfile untuk build image backend baseline
    │   ├── Dockerfile-optimized           <- Dockerfile untuk versi optimized
    │   ├── app.py                         <- Source code Flask backend (baseline)
    │   ├── app_optimized.py               <- Source code Flask backend (versi optimized)
    │   ├── requirements.txt               <- Dependensi Python untuk baseline
    │   └── requirements-optimized.txt     <- Dependensi Python untuk versi optimized
    ├── DB/
    │   ├── README.md                      <- Dokumentasi struktur dump database
    │   ├── generate_dump.py               <- Script pembuatan data realistis (seed)
    │   ├── init-indexes.js                <- Script inisialisasi index MongoDB
    │   ├── init-mongo.sh                  <- Script init otomatis saat container MongoDB pertama berjalan
    │   └── dump/
    │       └── orderdb/                   <- Berkas dump BSON MongoDB
    │           ├── audit_logs.bson
    │           ├── audit_logs.metadata.json
    │           ├── orders.bson
    │           ├── orders.metadata.json
    │           ├── products.bson
    │           ├── products.metadata.json
    │           ├── sessions.bson
    │           ├── sessions.metadata.json
    │           ├── users.bson
    │           └── users.metadata.json
    ├── FE/
    │   ├── index.html                     <- Halaman frontend utama
    │   └── styles.css                     <- Stylesheet frontend
    └── Test/
        └── locustfile.py                  <- Script load testing Locust
```

---

## Baseline Architecture

Implementasi baseline dirancang sebagai konfigurasi paling sederhana: seluruh komponen sistem berjalan dalam satu VM tunggal di DigitalOcean tanpa load balancer dan tanpa pemisahan service ke VM terpisah.

### Komponen Utama

**Container nginx (fp_nginx_baseline)**
Menjalankan image `nginx:1.25-alpine`. Merupakan satu-satunya service yang mengekspos port ke luar host (port 80). Melayani berkas frontend statis secara langsung dan meneruskan request API ke container backend melalui named upstream `flask_backend`. Konfigurasi diambil dari berkas `nginx.conf` pada root project. Batas memori container: 256 MB.

**Container backend (fp_backend_baseline)**
Dibangun dari `Resources/BE/Dockerfile` menggunakan base image `python:3.11-slim`. Menjalankan aplikasi Flask melalui Gunicorn dengan 8 worker process bertipe `gthread` dan 2 thread per worker. Port 5000 tidak diekspos ke luar host, hanya dapat diakses oleh container Nginx melalui jaringan internal Docker `app_net`. Batas memori container: 3 GB.

**Container mongo (fp_mongo_baseline)**
Menjalankan image `mongo:7.0`. Port 27017 tidak diekspos ke luar host. Data disimpan pada Docker volume persisten `mongo_data` dan `mongo_config`. Saat volume pertama kali dibuat, skrip `init-mongo.sh` dijalankan secara otomatis untuk melakukan seeding data awal dari dump BSON. WiredTiger cache dibatasi 2 GB. Batas memori container: 3 GB.

### Jaringan Docker

Seluruh container terhubung melalui Docker bridge network bernama `app_net` dengan subnet `172.20.0.0/24`. Komunikasi antar service menggunakan nama service sebagai hostname (misalnya `backend:5000` dan `mongo:27017`).

### Urutan Startup

Docker Compose mengelola urutan startup menggunakan `depends_on` dan `healthcheck`:
1. Container `mongo` dijalankan pertama. Siap setelah healthcheck `mongosh ping` berhasil.
2. Container `backend` dijalankan setelah `mongo` healthy. Siap setelah healthcheck `curl /health` berhasil.
3. Container `nginx` dijalankan setelah `backend` healthy.

### Alokasi Memori VM (8 GB RAM)

| Komponen | Batas (Limit) | Reservasi | Estimasi Aktual |
|---|---|---|---|
| MongoDB | 3 GB | 512 MB | 2 - 3 GB |
| Gunicorn + Flask | 3 GB | 256 MB | 800 MB - 1,5 GB |
| Nginx | 256 MB | 64 MB | 20 - 50 MB |
| Docker daemon + OS | Tidak dibatasi | Tidak dibatasi | 300 - 500 MB |
| Total | sekitar 6,5 GB soft limit | | maksimal 8 GB |

---

## Configuration Analysis

Berkas `config-baseline.md` mendokumentasikan secara lengkap seluruh parameter konfigurasi yang digunakan pada implementasi baseline.

### Parameter Nginx (nginx.conf)

| Parameter | Nilai | Keterangan |
|---|---|---|
| `worker_processes` | `auto` (terdeteksi 2) | Otomatis menyesuaikan jumlah CPU core |
| `worker_connections` | 1024 | Jumlah koneksi maksimum per worker |
| `keepalive_timeout` | 75 detik | Durasi koneksi persisten dari klien |
| `keepalive_requests` | 1000 | Jumlah request maksimum per koneksi |
| `gzip` | aktif (level 4) | Kompresi response JSON dan aset statis |
| `proxy_read_timeout` | 120 detik | Batas waktu tunggu respons dari backend |
| `upstream keepalive` | 32 | Koneksi persisten ke upstream backend |
| Port publik | 80 | Satu-satunya port yang diekspos ke luar |

Konfigurasi upstream Nginx pada baseline hanya mengarah ke satu server:

```nginx
upstream flask_backend {
    server backend:5000;
    keepalive 32;
}
```

### Parameter Gunicorn

| Parameter | Nilai | Keterangan |
|---|---|---|
| `--workers` | 8 | Jumlah worker process |
| `--threads` | 2 | Thread per worker |
| `--worker-class` | `gthread` | Tipe worker untuk workload I/O-bound |
| `--timeout` | 120 detik | Worker direstart jika tidak merespons dalam waktu ini |
| `--bind` | `0.0.0.0:5000` | Alamat dan port binding internal |
| Total slot konkuren | 16 | Hasil dari 8 workers x 2 threads |

### Parameter MongoDB

| Parameter | Nilai | Keterangan |
|---|---|---|
| Versi | 7.0 LTS | Versi MongoDB yang digunakan |
| `wiredTigerCacheSizeGB` | 2 | Ukuran cache WiredTiger dalam GB |
| Port | 27017 | Port internal, tidak diekspos ke host |
| Database | `orderdb` | Nama database utama |
| Autentikasi | username dan password | Dikonfigurasi via environment variable |

### Environment Variables

| Variabel | Nilai Default | Keterangan |
|---|---|---|
| `MONGO_URI` | `mongodb://admin:***@mongo:27017/orderdb?authSource=admin` | URI koneksi MongoDB |
| `JWT_SECRET` | (string acak panjang) | Kunci rahasia untuk signing token JWT |
| `JWT_EXPIRES` | 86400 | Masa berlaku token dalam detik (24 jam) |
| `GUNICORN_WORKERS` | 8 | Jumlah worker Gunicorn |
| `GUNICORN_THREADS` | 2 | Jumlah thread per worker |
| `GUNICORN_WORKER_CLASS` | `gthread` | Tipe worker Gunicorn |
| `GUNICORN_TIMEOUT` | 120 | Timeout worker dalam detik |
| `MONGO_INITDB_ROOT_USERNAME` | (diisi di .env) | Username root MongoDB |
| `MONGO_INITDB_ROOT_PASSWORD` | (diisi di .env) | Password root MongoDB |
| `MONGO_INITDB_DATABASE` | `orderdb` | Nama database inisialisasi MongoDB |

### Mapping Port

| Service | Port Internal | Port Eksternal | Aksesibilitas |
|---|---|---|---|
| Nginx | 80 | 80 | Publik (internet) |
| Flask / Gunicorn | 5000 | Tidak diekspos | Jaringan internal Docker |
| MongoDB | 27017 | Tidak diekspos | Jaringan internal Docker |

---

## Data Flow

### Alur Request dari Klien

Berikut adalah alur lengkap sebuah request dari klien hingga menghasilkan respons:

1. Klien mengirimkan request HTTP ke VM pada port 80.
2. Nginx menerima request. Jika request mengarah ke berkas statis yang tersedia di `/usr/share/nginx/html`, Nginx melayaninya langsung.
3. Jika berkas statis tidak ditemukan, Nginx meneruskan request ke upstream `flask_backend` (container `backend:5000`) melalui jaringan Docker internal.
4. Gunicorn menerima request dan mendistribusikannya ke salah satu worker thread yang tersedia.
5. Worker Flask memproses request: memvalidasi token JWT (jika diperlukan), menjalankan logika bisnis, dan berkomunikasi dengan MongoDB melalui PyMongo.
6. MongoDB memproses query (baca atau tulis) dan mengembalikan hasil.
7. Flask mengserialkan hasil (konversi ObjectId dan datetime ke string) dan mengembalikan respons JSON.
8. Respons dikirimkan kembali melalui Gunicorn ke Nginx, kemudian ke klien.

### Alur Data Seeding Database

Saat container MongoDB pertama kali diinisialisasi (volume masih kosong), skrip `init-mongo.sh` dijalankan secara otomatis. Skrip ini menjalankan `mongorestore` untuk mengimpor berkas dump BSON dari direktori `/docker-seed` (dipasang dari `Resources/DB/dump/orderdb`) ke dalam database `orderdb`.

### Diagram Alur Data

```mermaid
sequenceDiagram
    participant C as Klien / Browser / Locust
    participant N as Nginx (port 80)
    participant FE as Berkas Statis Frontend
    participant G as Gunicorn (port 5000)
    participant F as Flask App
    participant M as MongoDB (port 27017)

    C->>N: HTTP Request (port 80)
    alt Request ke berkas statis
        N->>FE: Baca index.html / styles.css
        FE-->>N: Konten berkas
        N-->>C: Respons HTML/CSS
    else Request ke API
        N->>G: Proxy HTTP ke backend:5000
        G->>F: Distribusi ke worker thread
        F->>F: Validasi JWT (jika endpoint terlindungi)
        F->>M: Query / Insert / Update (PyMongo)
        M-->>F: Hasil query (dokumen BSON)
        F->>F: Serialisasi (ObjectId dan datetime ke string)
        F-->>G: Respons JSON
        G-->>N: Respons JSON
        N-->>C: Respons JSON
    end
```

---

## Core Modules

| Modul | Lokasi | Deskripsi |
|---|---|---|
| Flask REST API | `Resources/BE/app.py` | Modul utama backend. Mendefinisikan seluruh endpoint REST API, middleware autentikasi JWT, logika bisnis pemrosesan pesanan, manajemen produk, manajemen pengguna, statistik admin, dan audit log. |
| Locust Load Testing | `Resources/Test/locustfile.py` | Mendefinisikan dua kelas pengguna virtual (CustomerUser dengan bobot 80% dan AdminUser dengan bobot 20%) beserta seluruh skenario pengujian beban yang mensimulasikan perilaku pengguna nyata. |
| Database Seeder | `Resources/DB/generate_dump.py` | Script Python untuk menghasilkan data realistis berbahasa Indonesia (produk, pengguna, pesanan, audit log, sesi) menggunakan library Faker dan mengekspornya ke format BSON dump MongoDB. |
| MongoDB Init Script | `Resources/DB/init-mongo.sh` | Skrip shell yang dijalankan otomatis oleh container MongoDB pada inisialisasi pertama untuk melakukan seeding database dari dump BSON. |
| MongoDB Index Script | `Resources/DB/init-indexes.js` | Skrip JavaScript MongoDB yang mendefinisikan seluruh index untuk collection `orders`, `products`, `users`, dan `audit_logs` guna mengoptimalkan performa query. |
| Database Restore Utility | `restore-db.sh` | Skrip shell interaktif untuk melakukan `mongorestore` ke dalam Docker container atau ke MongoDB yang berjalan di host. |
| Frontend Interface | `Resources/FE/index.html` | Halaman web statis untuk membuat pesanan, mengecek status, memperbarui status, dan melihat riwayat pesanan melalui pemanggilan Fetch API. |
| Frontend Stylesheet | `Resources/FE/styles.css` | Stylesheet CSS untuk tampilan antarmuka frontend. |
| Docker Compose Baseline | `docker-compose-baseline.yml` | Berkas orkestrasi Docker Compose yang mendefinisikan tiga service (mongo, backend, nginx), jaringan `app_net`, dan volume untuk konfigurasi baseline. |
| Nginx Config Baseline | `nginx.conf` | Konfigurasi Nginx lengkap untuk konfigurasi baseline, mencakup pengaturan upstream, gzip, buffer, timeout, dan serving berkas statis. |
| Backend Dockerfile | `Resources/BE/Dockerfile` | Instruksi build image Docker untuk backend Flask, berbasis `python:3.11-slim` dengan penambahan user non-root untuk keamanan. |

---

## Script Analysis

| Berkas | Tujuan | Fungsi-Fungsi Utama |
|---|---|---|
| `Resources/BE/app.py` | Backend REST API Flask utama | `register()`: registrasi pengguna baru dengan hashing password bcrypt. `login()`: autentikasi dan penerbitan token JWT. `me()`: informasi pengguna yang sedang login. `list_products()`: daftar produk dengan filter kategori, pencarian teks, pagination, dan sorting. `get_product()`: detail satu produk berdasarkan ID. `create_product()`: tambah produk baru (admin). `update_product()`: ubah data produk (admin). `delete_product()`: nonaktifkan produk secara soft delete (admin). `create_order()`: buat pesanan dengan validasi stok, pengurangan stok, dan kalkulasi total. `list_orders()`: daftar pesanan dengan filter status dan kota, pagination. `get_order()`: detail satu pesanan berdasarkan `order_id`. `update_order_status()`: ubah status pesanan (admin). `create_order_simple()`: buat pesanan tanpa autentikasi (digunakan oleh frontend). `get_order_simple()` dan `update_order_simple()`: endpoint sederhana untuk frontend. `admin_list_users()`: daftar pengguna dengan filter. `suspend_user()`: aktifkan atau nonaktifkan akun pengguna. `delete_user()`: hapus akun pengguna. `admin_stats()`: statistik dashboard (revenue, top produk, tren bulanan, distribusi kota). `admin_logs()`: daftar audit log dengan pagination. `health()`: health check endpoint. `serialize()`: konversi ObjectId dan datetime ke format JSON-safe. `make_token()`: pembuatan token JWT. `write_log()`: pencatatan aksi admin ke collection `audit_logs`. `login_required` dan `admin_required`: decorator autentikasi dan otorisasi. |
| `Resources/Test/locustfile.py` | Script load testing Locust | `CustomerUser.on_start()`: login sebagai pengguna acak dari database, cache daftar produk. `CustomerUser.browse_products()`: simulasi browsing katalog dengan filter acak (bobot task: 4). `CustomerUser.view_product_detail()`: simulasi melihat detail produk (bobot task: 2). `CustomerUser.create_order()`: simulasi pembuatan pesanan dengan item acak (bobot task: 3). `CustomerUser.my_orders()`: simulasi melihat riwayat pesanan (bobot task: 2). `CustomerUser.get_order_detail()`: simulasi melihat detail satu pesanan (bobot task: 1). `AdminUser.on_start()`: login sebagai admin acak. `AdminUser.dashboard_stats()`: simulasi akses dashboard statistik (bobot task: 4). `AdminUser.list_all_orders()`: simulasi admin melihat semua pesanan (bobot task: 3). `AdminUser.update_order_status()`: simulasi update status pesanan (bobot task: 2). `AdminUser.list_users()`: simulasi manajemen pengguna (bobot task: 2). `AdminUser.view_audit_logs()`: simulasi melihat audit log (bobot task: 1). |
| `Resources/DB/generate_dump.py` | Pembuatan data realistis untuk seeding | Generasi 96 produk dari katalog tetap dalam 7 kategori. Generasi 505 pengguna (5 admin + 500 pengguna biasa) menggunakan Faker bahasa Indonesia. Generasi 10.000 dokumen pesanan dengan distribusi status realistis. Generasi 2.000 entri audit log. Generasi 100 sesi pengguna. Ekspor semua data ke format BSON dump (`dump/orderdb/`). |
| `Resources/DB/init-mongo.sh` | Inisialisasi otomatis database saat container pertama berjalan | Menjalankan `mongorestore` untuk mengimpor dump BSON dari `/docker-seed` ke database `orderdb`. Menampilkan jumlah dokumen per collection setelah seeding. |
| `Resources/DB/init-indexes.js` | Pembuatan index MongoDB | Membuat 6 index pada collection `orders` (termasuk index unik pada `order_id`). Membuat 4 index pada collection `products` (compound index untuk filter aktif dan berbagai sorting). Membuat 3 index pada collection `users` (index unik pada `email`). Membuat 2 index pada collection `audit_logs`. |
| `restore-db.sh` | Utility restore database interaktif | Membaca konfigurasi dari berkas `.env`. Menyediakan dua pilihan: restore ke Docker container (`fp_mongo_optimized`) atau ke MongoDB host lokal. Menjalankan `mongorestore` dengan autentikasi dari environment variable. |
| `scratch.py` | Pengujian koneksi MongoDB | Pengujian koneksi sederhana ke `mongodb://localhost:27017` menggunakan PyMongo. |

---

## Processing Workflow

### Alur Kerja Deployment

1. Administrator menyiapkan berkas `.env` dengan mengisi nilai untuk `MONGO_INITDB_ROOT_USERNAME`, `MONGO_INITDB_ROOT_PASSWORD`, `MONGO_INITDB_DATABASE`, `MONGO_URI`, `JWT_SECRET`, dan parameter Gunicorn.
2. Docker Compose membaca `docker-compose-baseline.yml` dan membangun image backend dari `Resources/BE/Dockerfile`.
3. Container `mongo` dijalankan. Pada startup pertama, skrip `init-mongo.sh` secara otomatis mengimpor data awal dari dump BSON yang dipasang dari `Resources/DB/dump/orderdb`.
4. Setelah MongoDB dinyatakan sehat oleh healthcheck, container `backend` dijalankan. Gunicorn memulai 8 worker process dengan tipe `gthread`.
5. Setelah backend dinyatakan sehat, container `nginx` dijalankan dan siap menerima traffic dari luar.

### Alur Kerja Request Pengguna Akhir

1. Pengguna mengakses halaman web melalui browser. Nginx melayani `index.html` dan `styles.css` dari direktori statis.
2. Pengguna mengisi formulir pembuatan pesanan (nama produk, jumlah, harga satuan) dan menekan tombol.
3. JavaScript di halaman menggunakan Fetch API untuk mengirimkan `POST /order` ke server.
4. Flask menerima request, membuat dokumen pesanan dengan UUID unik, menyimpannya ke collection `orders` di MongoDB, dan mengembalikan dokumen pesanan dalam format JSON.
5. Pengguna dapat menggunakan Order ID yang dikembalikan untuk mengecek status via `GET /order/<order_id>` atau memperbarui status via `PUT /order/<order_id>`.
6. Riwayat seluruh pesanan dapat dilihat melalui `GET /orders`.

### Alur Kerja Load Testing

1. Locust dijalankan dari komputer yang berbeda dari server aplikasi.
2. Locust membuat sejumlah pengguna virtual (CustomerUser 80% dan AdminUser 20%).
3. Setiap `CustomerUser` melakukan login dengan email pengguna acak dari database, melakukan cache daftar produk, kemudian secara acak menjalankan task: browse produk, lihat detail produk, buat pesanan, lihat riwayat pesanan, atau lihat detail satu pesanan.
4. Setiap `AdminUser` melakukan login sebagai admin, kemudian secara acak menjalankan task: akses dashboard statistik, lihat semua pesanan, update status pesanan, lihat pengguna, atau lihat audit log.
5. Locust mencatat RPS, response time, dan failure rate selama durasi pengujian yang ditentukan.

---

## Storage Design

### Format Data

Seluruh data disimpan dalam format dokumen BSON (Binary JSON) oleh MongoDB. Komunikasi antara backend Python dan MongoDB menggunakan library PyMongo dengan tipe data native Python yang dikonversi otomatis ke BSON.

### Struktur Database

Database utama bernama `orderdb` dan terdiri dari lima collection berikut:

**Collection `users`** (505 dokumen awal)

| Field | Tipe | Keterangan |
|---|---|---|
| `_id` | ObjectId | Primary key MongoDB |
| `name` | String | Nama lengkap pengguna |
| `email` | String | Email unik (index unik) |
| `password` | String | Hash bcrypt |
| `role` | String | Nilai: `"admin"` atau `"user"` |
| `city` | String | Kota pengguna |
| `phone` | String | Nomor telepon |
| `address` | String | Alamat lengkap |
| `is_active` | Boolean | Status akun aktif atau dinonaktifkan |
| `created_at` | Date | Waktu pembuatan akun |
| `updated_at` | Date | Waktu pembaruan terakhir |
| `last_login` | Date atau null | Waktu login terakhir |

**Collection `products`** (96 dokumen awal, 7 kategori)

| Field | Tipe | Keterangan |
|---|---|---|
| `_id` | ObjectId | Primary key MongoDB |
| `name` | String | Nama produk |
| `category` | String | Kategori produk |
| `price` | Float | Harga satuan |
| `stock` | Integer | Jumlah stok tersedia |
| `rating` | Float | Rating rata-rata |
| `rating_count` | Integer | Jumlah penilai |
| `description` | String | Deskripsi produk |
| `image_url` | String | URL gambar produk |
| `is_active` | Boolean | Status produk aktif |
| `created_at` | Date | Waktu pembuatan |
| `updated_at` | Date | Waktu pembaruan |

**Collection `orders`** (10.000 dokumen awal)

| Field | Tipe | Keterangan |
|---|---|---|
| `_id` | ObjectId | Primary key MongoDB |
| `order_id` | String | UUID unik pesanan (index unik) |
| `user_id` | ObjectId atau null | Referensi ke pengguna |
| `customer_name` | String | Nama pelanggan |
| `customer_email` | String | Email pelanggan |
| `customer_city` | String | Kota pelanggan |
| `customer_address` | String | Alamat pengiriman |
| `items` | Array | Daftar item pesanan (product_id, product_name, category, qty, price, subtotal) |
| `subtotal` | Float | Total sebelum diskon dan ongkir |
| `discount_pct` | Integer | Persentase diskon |
| `discount_amt` | Float | Nominal diskon |
| `shipping_cost` | Integer | Biaya pengiriman |
| `total` | Float | Total akhir |
| `status` | String | Nilai: `pending`, `processing`, `completed`, `cancelled` |
| `payment_method` | String | Metode pembayaran |
| `payment_status` | String | Nilai: `paid` atau `unpaid` |
| `notes` | String | Catatan pesanan |
| `created_at` | Date | Waktu pesanan dibuat |
| `updated_at` | Date | Waktu pembaruan terakhir |

**Collection `audit_logs`** (2.000 dokumen awal)

| Field | Tipe | Keterangan |
|---|---|---|
| `_id` | ObjectId | Primary key MongoDB |
| `admin_id` | ObjectId | Referensi ke admin yang melakukan aksi |
| `action` | String | Jenis aksi (misalnya `update_order_status`, `suspend_user`) |
| `collection` | String | Nama collection yang menjadi target aksi |
| `target_id` | String | ID entitas yang menjadi target |
| `detail` | Object | Detail tambahan aksi |
| `created_at` | Date | Waktu aksi dilakukan |

**Collection `sessions`** (100 dokumen awal)

| Field | Tipe | Keterangan |
|---|---|---|
| `_id` | ObjectId | Primary key MongoDB |
| `user_id` | ObjectId | Referensi ke pengguna |
| `token_hash` | String | Hash token sesi |
| `expires_at` | Date | Waktu kedaluwarsa sesi |
| `created_at` | Date | Waktu sesi dibuat |

### Index MongoDB

Index yang dibuat secara otomatis oleh skrip `init-indexes.js`:

**Collection `orders`:**
- `idx_orders_created_at_desc`: `{ created_at: -1 }`
- `idx_orders_order_id_unique`: `{ order_id: 1 }` (unik)
- `idx_orders_status`: `{ status: 1 }`
- `idx_orders_status_created_desc`: `{ status: 1, created_at: -1 }` (compound)
- `idx_orders_customer_city`: `{ customer_city: 1 }`
- `idx_orders_user_id_created`: `{ user_id: 1, created_at: -1 }` (compound)

**Collection `products`:**
- `idx_products_active_created_desc`: `{ is_active: 1, created_at: -1 }` (compound)
- `idx_products_active_category`: `{ is_active: 1, category: 1 }` (compound)
- `idx_products_active_price`: `{ is_active: 1, price: 1 }` (compound)
- `idx_products_active_rating_desc`: `{ is_active: 1, rating: -1 }` (compound)

**Collection `users`:**
- `idx_users_email_unique`: `{ email: 1 }` (unik)
- `idx_users_role`: `{ role: 1 }`
- `idx_users_role_active`: `{ role: 1, is_active: 1 }` (compound)

**Collection `audit_logs`:**
- `idx_logs_created_at_desc`: `{ created_at: -1 }`
- `idx_logs_admin_id_created`: `{ admin_id: 1, created_at: -1 }` (compound)

### Persistensi Data

Data MongoDB disimpan pada Docker volume bernama `mongo_data` dan `mongo_config`. Volume ini persisten di antara restart container. Dump awal disimpan dalam format BSON di `Resources/DB/dump/orderdb/`.

---

## API Documentation

Backend Flask menyediakan dua kelompok endpoint: endpoint utama dengan autentikasi JWT dan endpoint sederhana yang digunakan oleh frontend tanpa autentikasi.

### Autentikasi

Endpoint yang dilindungi memerlukan header `Authorization: Bearer <token>`. Token JWT diperoleh melalui endpoint `/auth/login` atau `/auth/register`. Token berlaku selama `JWT_EXPIRES` detik (default: 86.400 detik atau 24 jam).

### Endpoint Autentikasi

| Method | Endpoint | Auth | Deskripsi |
|---|---|---|---|
| POST | `/auth/register` | Tidak | Registrasi pengguna baru |
| POST | `/auth/login` | Tidak | Login dan memperoleh token JWT |
| GET | `/auth/me` | User | Informasi pengguna yang sedang login |

**POST `/auth/register`**

Request body:
```json
{
  "name": "Nama Lengkap",
  "email": "email@contoh.com",
  "password": "kata_sandi",
  "city": "Surabaya",
  "phone": "08123456789",
  "address": "Jl. Contoh No. 1"
}
```

Response (201 Created):
```json
{
  "message": "Registrasi berhasil",
  "token": "<jwt_token>",
  "user": { "id": "<id>", "name": "Nama", "email": "email@contoh.com", "role": "user" }
}
```

**POST `/auth/login`**

Request body:
```json
{ "email": "email@contoh.com", "password": "kata_sandi" }
```

Response (200 OK):
```json
{
  "token": "<jwt_token>",
  "user": { "id": "<id>", "name": "Nama", "email": "email@contoh.com", "role": "user" }
}
```

### Endpoint Produk

| Method | Endpoint | Auth | Deskripsi |
|---|---|---|---|
| GET | `/products` | Tidak | Daftar produk aktif dengan filter, pagination, sorting |
| GET | `/products/<product_id>` | Tidak | Detail satu produk |
| POST | `/products` | Admin | Tambah produk baru |
| PUT | `/products/<product_id>` | Admin | Perbarui data produk |
| DELETE | `/products/<product_id>` | Admin | Nonaktifkan produk (soft delete) |

**GET `/products` — Parameter Query:**

| Parameter | Tipe | Keterangan |
|---|---|---|
| `category` | String | Filter berdasarkan kategori produk |
| `search` | String | Pencarian teks pada nama produk (regex) |
| `page` | Integer | Nomor halaman (default: 1) |
| `limit` | Integer | Jumlah item per halaman (default: 20, maks: 100) |
| `sort` | String | Nilai: `price_asc`, `price_desc`, `rating`, `newest` |

### Endpoint Pesanan (Lengkap, dengan Auth)

| Method | Endpoint | Auth | Deskripsi |
|---|---|---|---|
| POST | `/orders` | User | Buat pesanan baru dengan validasi stok |
| GET | `/orders` | Tidak | Daftar semua pesanan dengan filter dan pagination |
| GET | `/orders/<order_id>` | Tidak | Detail satu pesanan |
| PUT | `/orders/<order_id>/status` | Admin | Perbarui status pesanan |

**POST `/orders`** — Request body:
```json
{
  "items": [{ "product_id": "<id>", "qty": 2 }],
  "payment_method": "transfer_bank",
  "shipping_cost": 15000,
  "address": "Jl. Contoh No. 1, Surabaya",
  "customer_name": "Nama Pelanggan",
  "customer_email": "pelanggan@contoh.com",
  "city": "Surabaya",
  "notes": "Catatan opsional"
}
```

### Endpoint Sederhana (Digunakan oleh Frontend)

| Method | Endpoint | Auth | Deskripsi |
|---|---|---|---|
| POST | `/order` | Tidak | Buat pesanan tanpa autentikasi |
| GET | `/order/<order_id>` | Tidak | Cek status pesanan berdasarkan order_id |
| PUT | `/order/<order_id>` | Tidak | Perbarui status pesanan tanpa autentikasi |

**POST `/order`** — Request body:
```json
{ "product": "Nama Produk", "quantity": 2, "price": 150000 }
```

Response (201 Created):
```json
{
  "order_id": "<uuid>",
  "product": "Nama Produk",
  "quantity": 2,
  "price": 150000.0,
  "total": 300000.0,
  "status": "pending",
  "created_at": "2026-06-24T10:00:00+00:00"
}
```

### Endpoint Admin

| Method | Endpoint | Auth | Deskripsi |
|---|---|---|---|
| GET | `/admin/users` | Admin | Daftar semua pengguna dengan filter |
| PUT | `/admin/users/<user_id>/suspend` | Admin | Aktifkan atau nonaktifkan akun pengguna |
| DELETE | `/admin/users/<user_id>` | Admin | Hapus akun pengguna |
| GET | `/admin/stats` | Admin | Statistik dashboard (revenue, top produk, tren bulanan, distribusi kota) |
| GET | `/admin/logs` | Admin | Daftar audit log dengan pagination |

### Health Check

| Method | Endpoint | Auth | Deskripsi |
|---|---|---|---|
| GET | `/health` | Tidak | Status kesehatan aplikasi backend |

Response:
```json
{ "status": "ok", "timestamp": "2026-06-24T10:00:00+00:00" }
```

### Format Respons Error

```json
{ "error": "Pesan error" }
```

HTTP status code yang digunakan: 400 (Bad Request), 401 (Unauthorized), 403 (Forbidden), 404 (Not Found), 409 (Conflict).

---

## Deployment Architecture

### Spesifikasi Infrastruktur Baseline

| Komponen | Detail |
|---|---|
| Cloud Provider | DigitalOcean |
| Tipe VM | Droplet Basic |
| vCPU | 4 |
| RAM | 8 GB |
| Disk | 160 GB SSD |
| Sistem Operasi | Ubuntu 24.04 LTS |
| Jumlah VM | 1 (all-in-one) |
| Biaya | $48 per bulan (sekitar Rp768.000 per bulan) |

### Diagram Deployment

```mermaid
flowchart LR
    subgraph Internet
        Client["Klien / Locust\n(Host Eksternal)"]
    end

    subgraph DO["DigitalOcean Droplet — $48/bulan\nUbuntu 24.04 | 4 vCPU | 8 GB RAM | 160 GB SSD"]
        subgraph DockerEngine["Docker Engine"]
            Nginx["Container: fp_nginx_baseline\nImage: nginx:1.25-alpine\nPort: 80 (expose)\nMem Limit: 256 MB\nVolume: nginx.conf (ro)\nVolume: Resources/FE/ (ro)"]
            Backend["Container: fp_backend_baseline\nImage: fp_backend_baseline:latest\nBuild: Resources/BE/Dockerfile\nBase: python:3.11-slim\nPort: 5000 (internal)\nMem Limit: 3 GB"]
            MongoDB["Container: fp_mongo_baseline\nImage: mongo:7.0\nPort: 27017 (internal)\nMem Limit: 3 GB\nVolume: mongo_data\nVolume: mongo_config"]
            Net["Docker Network: app_net\n172.20.0.0/24"]
        end
        Volume1["Docker Volume\nmongo_data"]
        Volume2["Docker Volume\nmongo_config"]
        DumpFiles["Resources/DB/dump/orderdb/\n(BSON seed, read-only mount)"]
    end

    Client -->|"HTTP :80"| Nginx
    Nginx -->|"proxy :5000\n(internal)"| Backend
    Backend -->|"TCP :27017\n(internal)"| MongoDB
    MongoDB --- Volume1
    MongoDB --- Volume2
    MongoDB --- DumpFiles
    Nginx ---|"app_net"| Net
    Backend ---|"app_net"| Net
    MongoDB ---|"app_net"| Net
```

### Tabel Biaya Infrastruktur Baseline

| Komponen | Spesifikasi | Harga per Bulan |
|---|---|---|
| Droplet Basic | 4 vCPU, 8 GB RAM, 160 GB SSD | $48,00 |
| Load Balancer | Tidak digunakan | $0 |
| VM Tambahan | Tidak ada | $0 |
| Total | | $48,00 per bulan |

Dalam rupiah (kurs sekitar Rp16.000/USD): sekitar Rp768.000 per bulan. Nilai ini masih di bawah batas anggaran maksimal proyek sebesar Rp1.300.000 per bulan.

---

## Installation

### Prasyarat

- Docker dan Docker Compose terinstall pada VM.
- Akses SSH ke VM target (DigitalOcean Droplet atau setara).
- Git terinstall.

### Langkah Instalasi Docker di VM (Ubuntu 24.04)

```bash
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER
newgrp docker
```

### Clone Repository

```bash
git clone https://github.com/<org>/FP-TKA-B01.git
cd FP-TKA-B01
```

### Konfigurasi Environment

Buat berkas `.env` di direktori root project dengan isian berikut:

```env
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=GantiPasswordIni@2026
MONGO_INITDB_DATABASE=orderdb
MONGO_URI=mongodb://admin:GantiPasswordIni@2026@mongo:27017/orderdb?authSource=admin
JWT_SECRET=ganti-dengan-string-acak-panjang-minimal-32-karakter
JWT_EXPIRES=86400
GUNICORN_WORKERS=8
GUNICORN_THREADS=2
GUNICORN_WORKER_CLASS=gthread
GUNICORN_TIMEOUT=120
```

---

## Running the Project

### Menjalankan Baseline

```bash
# Build image backend dan jalankan seluruh service
docker compose -f docker-compose-baseline.yml up -d --build

# Memeriksa status container
docker compose -f docker-compose-baseline.yml ps

# Melihat log secara real-time
docker compose -f docker-compose-baseline.yml logs -f
```

### Verifikasi Sistem

```bash
# Test health check backend
curl http://localhost/health

# Test endpoint produk
curl http://localhost/products

# Test endpoint pesanan (POST)
curl -X POST http://localhost/order \
  -H "Content-Type: application/json" \
  -d '{"product": "Laptop Test", "quantity": 1, "price": 5000000}'
```

### Restore Database Secara Manual (Jika Diperlukan)

```bash
# Salin dump ke dalam container MongoDB
docker cp Resources/DB/dump fp_mongo_baseline:/tmp/dump

# Jalankan mongorestore di dalam container
docker exec fp_mongo_baseline mongorestore \
  --uri="mongodb://admin:GantiPasswordIni@2026@localhost:27017" \
  --authSource=admin \
  --drop /tmp/dump
```

Atau gunakan skrip interaktif yang tersedia:

```bash
bash restore-db.sh
```

### Menjalankan Load Testing (dari Host Terpisah)

Locust harus dijalankan dari komputer yang berbeda dari server aplikasi.

```bash
# Install Locust di host penguji
pip install locust

# Jalankan Locust dengan target server
locust -f Resources/Test/locustfile.py --host=http://<IP_SERVER>
```

Akses antarmuka web Locust di `http://localhost:8089` untuk mengatur jumlah pengguna dan spawn rate.

### Menghentikan Sistem

```bash
docker compose -f docker-compose-baseline.yml down

# Menghentikan dan menghapus volume (data akan hilang)
docker compose -f docker-compose-baseline.yml down -v
```

---

## Baseline Experiment Results

Pengujian baseline dilakukan dengan menjalankan Locust dari host eksternal yang berbeda dari server aplikasi, mengikuti 5 skenario yang telah ditetapkan dalam spesifikasi Final Project.

### Struktur Laporan Baseline

Hasil pengujian disimpan dalam folder `Report/baseline/` dengan struktur berikut:

```text
Report/baseline/
├── hasil_pengujian.md   <- Catatan skenario pengujian
├── try_1/
│   ├── image-1.png      <- Screenshot hasil Locust (RPS, response time, failure rate)
│   └── resource.png     <- Screenshot resource utilization (CPU, memory) server
├── try_2/
│   ├── image.png
│   └── resource.png
├── try_3/
│   ├── image-2.png
│   └── resource.png
├── try_4/
│   ├── image-3.png
│   └── resource.png
└── try_5/
    ├── image-4.png
    └── resource.png
```

### Skenario Pengujian

Pengujian dilakukan dalam 5 skenario sesuai spesifikasi:

| Skenario | Deskripsi | Durasi |
|---|---|---|
| Skenario 1 | Maksimum RPS dengan 0% failure (naikkan user secara bertahap) | 60 detik |
| Skenario 2 | Peak Concurrency — Spawn Rate 50 (tingkatkan hingga failure muncul, catat nilai sebelumnya) | 60 detik |
| Skenario 3 | Peak Concurrency — Spawn Rate 100 | 60 detik |
| Skenario 4 | Peak Concurrency — Spawn Rate 200 | 60 detik |
| Skenario 5 | Peak Concurrency — Spawn Rate 500 | 60 detik |

### Estimasi Performa Teoritis Baseline

Berdasarkan konfigurasi yang diimplementasikan (sebagaimana didokumentasikan dalam `config-baseline.md`), berikut adalah estimasi performa teoritis sebelum pengujian:

| Metrik | Estimasi |
|---|---|
| Slot konkuren Gunicorn | 16 (8 workers x 2 threads) |
| Koneksi maksimum Nginx | sekitar 4.096 (4 worker processes x 1.024 koneksi) |
| Target RPS untuk request GET sederhana | 150 - 400 RPS |
| Target RPS untuk request POST pesanan | 80 - 200 RPS |
| Bottleneck utama yang diidentifikasi | MongoDB single instance dengan WiredTiger cache 2 GB |

### Catatan Pengujian

Setiap skenario dilakukan dengan menghapus data yang diinsert selama skenario sebelumnya (data pesanan yang dibuat oleh Locust) agar tidak terjadi akumulasi data yang mempengaruhi performa query. Data awal database (505 pengguna, 96 produk, 10.000 pesanan awal, 2.000 audit log) tetap dipertahankan.

Hasil pengujian aktual (nilai RPS, response time, concurrent user, dan grafik) tersimpan dalam berkas gambar di masing-masing subdirektori `try_1` hingga `try_5` dalam folder `Report/baseline/`.

---

## Limitations

Berdasarkan analisis implementasi dan dokumentasi konfigurasi baseline, keterbatasan-keterbatasan berikut dapat diidentifikasi:

**Single Point of Failure**
Seluruh komponen (Nginx, Flask/Gunicorn, MongoDB) berjalan pada satu VM. Jika VM mengalami gangguan, seluruh layanan berhenti beroperasi.

**Tidak Ada Load Balancing**
Nginx dikonfigurasi sebagai reverse proxy sederhana tanpa kemampuan mendistribusikan beban ke beberapa instance backend. Sistem tidak dapat diskalakan secara horizontal pada konfigurasi ini.

**MongoDB Berbagi Sumber Daya dengan Backend**
MongoDB dan Flask/Gunicorn berjalan pada VM yang sama dan saling bersaing dalam penggunaan CPU dan RAM. Hal ini menjadi bottleneck utama pada kondisi beban tinggi, khususnya untuk operasi write-heavy seperti pembuatan pesanan dan query agregasi dashboard.

**Kapasitas Konkuren Terbatas**
Dengan konfigurasi 8 workers x 2 threads, total slot konkuren hanya 16. Pada kondisi spike traffic, antrian request dapat menumpuk dan mengakibatkan peningkatan response time.

**Tidak Ada CDN**
Frontend dilayani langsung dari Nginx pada VM yang sama. Tidak ada mekanisme content delivery network untuk mengurangi latensi bagi pengguna di lokasi geografis yang berbeda.

**Tidak Ada Mekanisme Caching Aplikasi**
Backend tidak mengimplementasikan caching di sisi aplikasi (misalnya Redis) untuk hasil query yang sering diakses, seperti daftar produk atau statistik dashboard. Setiap request menghasilkan query baru ke MongoDB.

**Tidak Ada Monitoring atau Alerting Terintegrasi**
Repository tidak mencakup konfigurasi sistem monitoring atau alerting (seperti Prometheus, Grafana, atau sejenisnya) pada level infrastruktur.

**Collection `sessions` Tidak Terintegrasi dengan Logika Autentikasi**
Collection `sessions` dibuat dalam dump database, namun berdasarkan analisis `app.py`, autentikasi sepenuhnya berbasis stateless JWT. Collection `sessions` tidak digunakan oleh logika autentikasi pada kode baseline.

---

## Future Improvements

Berdasarkan kondisi repository dan keterbatasan yang diidentifikasi pada implementasi baseline, beberapa pengembangan yang relevan adalah sebagai berikut:

**Pemisahan MongoDB ke VM Terpisah**
Menempatkan MongoDB pada VM yang didedikasikan (tanpa berbagi sumber daya dengan backend) akan mengurangi kontesi CPU dan RAM secara signifikan, sehingga meningkatkan throughput keseluruhan sistem.

**Penerapan Load Balancer dengan Multiple Backend Instance**
Menambahkan beberapa instance backend (Flask/Gunicorn) di belakang load balancer Nginx atau DigitalOcean Load Balancer akan memungkinkan distribusi beban dan peningkatan kapasitas konkuren secara horizontal.

**Penggunaan Worker Class `gevent` pada Gunicorn**
Mengganti tipe worker dari `gthread` ke `gevent` berpotensi meningkatkan jumlah request konkuren yang dapat ditangani oleh setiap worker, khususnya untuk workload yang bersifat I/O-bound.

**Implementasi Caching dengan Redis**
Menambahkan layer caching menggunakan Redis untuk hasil query yang sering diakses (seperti daftar produk aktif dan statistik dashboard) akan mengurangi beban query ke MongoDB secara signifikan.

**Penerapan Connection Pooling MongoDB yang Lebih Tertuning**
Mengkonfigurasi parameter connection pool PyMongo (seperti `maxPoolSize` dan `minPoolSize`) secara eksplisit sesuai dengan kapasitas server.

**Penambahan Monitoring dan Observabilitas**
Mengintegrasikan sistem monitoring seperti Prometheus dan Grafana, atau memanfaatkan fitur monitoring bawaan DigitalOcean, untuk pemantauan metrik CPU, RAM, dan throughput secara real-time.

**Penerapan HTTPS**
Menambahkan sertifikat TLS/SSL pada Nginx untuk mengamankan komunikasi antara klien dan server, yang merupakan persyaratan standar untuk lingkungan produksi.

---

## Conclusion

Implementasi baseline pada proyek Final Project Teknologi Komputasi Awan 2026 ini berhasil mendeploy sebuah Order Processing Service yang fungsional dalam arsitektur all-in-one menggunakan Docker Compose pada satu Droplet DigitalOcean senilai $48 per bulan.

Sistem terdiri dari tiga komponen yang saling bekerja sama dalam jaringan Docker internal: Nginx sebagai reverse proxy dan server frontend statis, Flask dengan Gunicorn sebagai backend REST API dengan total 16 slot konkuren, serta MongoDB sebagai basis data penyimpanan seluruh data bisnis.

Backend mengimplementasikan fungsionalitas lengkap yang mencakup autentikasi berbasis JWT, manajemen produk, pemrosesan pesanan dengan validasi stok, manajemen pengguna untuk admin, statistik dashboard berbasis agregasi MongoDB, dan sistem audit log. Index MongoDB yang komprehensif turut dikonfigurasi untuk mengoptimalkan performa query pada collection yang paling sering diakses.

Konfigurasi baseline ini berfungsi sebagai titik awal pengukuran (baseline measurement) sebelum dilakukan optimasi lebih lanjut. Hasil load testing Locust yang direkam dalam folder `Report/baseline/` memberikan data empiris tentang kemampuan maksimum sistem pada konfigurasi ini. Keterbatasan utama yang diidentifikasi, yaitu tidak adanya load balancer, seluruh komponen berbagi sumber daya pada satu VM, dan tidak adanya layer caching, menjadi dasar bagi pengembangan konfigurasi berikutnya.

Secara keseluruhan, implementasi baseline ini menunjukkan pemahaman yang baik terhadap konsep deployment berbasis container pada infrastruktur cloud, dengan konfigurasi yang didokumentasikan secara rinci dan dapat direproduksi.

---
