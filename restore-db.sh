#!/bin/bash
# ==============================================================================
# restore-db.sh
# Script untuk mongorestore database MongoDB (Local atau Docker Container)
# FP Teknologi Komputasi Awan 2026 — Kelompok B01
# ==============================================================================

# Berhenti jika ada error
set -e

# Warna output terminal
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# File .env relatif ke lokasi script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Muat variabel dari .env jika ada
if [ -f "$ENV_FILE" ]; then
    echo -e "${GREEN}ℹ️ Memuat konfigurasi dari $ENV_FILE...${NC}"
    # Membaca .env, mengabaikan baris kosong dan komentar, lalu mengekspor variabel
    export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# Tentukan default parameter jika tidak diset di .env
DB_NAME=${MONGO_INITDB_DATABASE:-"orderdb"}
DB_USER=${MONGO_INITDB_ROOT_USERNAME:-"admin"}
DB_PASS=${MONGO_INITDB_ROOT_PASSWORD:-"TKAB01@2026"}
DUMP_PATH="$SCRIPT_DIR/Resources/DB/dump"
CONTAINER_NAME=${MONGO_CONTAINER_NAME:-"fp_mongo_baseline"}

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}        MongoDB Restore Database Utility            ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Informasi Konfigurasi:"
echo -e "  - Target Database : ${YELLOW}$DB_NAME${NC}"
echo -e "  - Username        : ${YELLOW}$DB_USER${NC}"
echo -e "  - Folder Dump     : ${YELLOW}$DUMP_PATH${NC}"
echo -e "  - Docker Container: ${YELLOW}$CONTAINER_NAME${NC}"
echo -e "${GREEN}====================================================${NC}"

# Cek apakah folder dump ada
if [ ! -d "$DUMP_PATH" ]; then
    echo -e "${RED}Error: Folder dump tidak ditemukan di $DUMP_PATH${NC}"
    exit 1
fi

echo -e "Pilih metode restore:"
echo -e "1) Restore ke dalam ${GREEN}Docker Container${NC} ($CONTAINER_NAME)"
echo -e "2) Restore ke ${GREEN}MongoDB Lokal / Host${NC} (menggunakan mongorestore host)"
echo -e "3) Keluar"
read -p "Masukkan pilihan [1-3]: " PILIHAN

case $PILIHAN in
    1)
        echo -e "\n${YELLOW}▶ Memulai restore ke Docker Container ($CONTAINER_NAME)...${NC}"
        
        # Cek apakah Docker terinstall
        if ! command -v docker &> /dev/null; then
            echo -e "${RED}Error: Docker tidak ditemukan di sistem ini.${NC}"
            exit 1
        fi

        # Cek apakah container sedang berjalan
        if ! docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
            echo -e "${RED}Error: Container '$CONTAINER_NAME' tidak berjalan atau tidak ditemukan.${NC}"
            echo -e "Silakan jalankan container terlebih dahulu (misal: docker compose up -d)${NC}"
            exit 1
        fi

        # Hapus sisa dump lama di container jika ada, lalu salin dump baru
        echo -e "-> Menyalin folder dump ke dalam container..."
        docker exec -i "$CONTAINER_NAME" rm -rf /tmp/dump
        docker cp "$DUMP_PATH" "$CONTAINER_NAME:/tmp/dump"

        # Menjalankan mongorestore di dalam container
        echo -e "-> Menjalankan mongorestore..."
        if [ -n "$DB_USER" ] && [ -n "$DB_PASS" ]; then
            docker exec -i "$CONTAINER_NAME" mongorestore \
                --username="$DB_USER" \
                --password="$DB_PASS" \
                --authenticationDatabase="admin" \
                --drop \
                /tmp/dump
        else
            docker exec -i "$CONTAINER_NAME" mongorestore \
                --drop \
                /tmp/dump
        fi

        # Hapus file dump sementara di dalam container
        docker exec -i "$CONTAINER_NAME" rm -rf /tmp/dump
        ;;

    2)
        echo -e "\n${YELLOW}▶ Memulai restore ke MongoDB Host/Lokal...${NC}"
        
        # Cek apakah mongorestore terinstall di host
        if ! command -v mongorestore &> /dev/null; then
            echo -e "${RED}Error: mongorestore tidak ditemukan di host ini.${NC}"
            echo -e "Silakan instal MongoDB Database Tools terlebih dahulu.${NC}"
            exit 1
        fi

        # Menjalankan mongorestore di host
        echo -e "-> Menjalankan mongorestore..."
        if [ -n "$DB_USER" ] && [ -n "$DB_PASS" ]; then
            mongorestore \
                --username="$DB_USER" \
                --password="$DB_PASS" \
                --authenticationDatabase="admin" \
                --drop \
                "$DUMP_PATH"
        else
            mongorestore \
                --drop \
                "$DUMP_PATH"
        fi
        ;;

    3)
        echo -e "${YELLOW}Dibatalkan.${NC}"
        exit 0
        ;;

    *)
        echo -e "${RED}Pilihan tidak valid.${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}✔ Database berhasil di-restore!${NC}"
