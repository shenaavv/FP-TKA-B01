#!/bin/bash
# =====================================================
# init-mongo.sh
# Otomatis di-run oleh MongoDB saat pertama kali init
# (hanya berjalan sekali selama volume mongo_data kosong)
# =====================================================
set -e

echo ""
echo "🌱 [init-mongo] Memulai seed database orderdb ..."
echo ""

mongorestore \
  --host 127.0.0.1 \
  --port 27017 \
  --db orderdb \
  /docker-seed/

echo ""
echo "✅ [init-mongo] Seed selesai! Collections:"
mongosh --quiet --eval "
  db = db.getSiblingDB('orderdb');
  print('  users    :', db.users.countDocuments());
  print('  products :', db.products.countDocuments());
  print('  orders   :', db.orders.countDocuments());
  print('  sessions :', db.sessions.countDocuments());
  print('  audit_logs:', db.audit_logs.countDocuments());
"
echo ""
