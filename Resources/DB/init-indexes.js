// =====================================================
// 02-init-indexes.js
// Membuat index MongoDB untuk optimasi performa query
// Dijalankan otomatis setelah 01-init-mongo.sh saat
// volume mongo_data pertama kali dibuat
// =====================================================

db = db.getSiblingDB('orderdb');

print("");
print("📌 [init-indexes] Membuat index untuk koleksi orderdb ...");
print("");

// ── orders collection ──────────────────────────────────────────────
// Index utama: sort by created_at (paling sering dipakai di list_orders)
db.orders.createIndex(
  { "created_at": -1 },
  { name: "idx_orders_created_at_desc" }
);

// Index unik: order_id (dipakai di get_order & update_order_status)
db.orders.createIndex(
  { "order_id": 1 },
  { unique: true, name: "idx_orders_order_id_unique" }
);

// Index: filter by status (list_orders dengan ?status=...)
db.orders.createIndex(
  { "status": 1 },
  { name: "idx_orders_status" }
);

// Compound index: status + created_at (admin list dengan filter + sort)
db.orders.createIndex(
  { "status": 1, "created_at": -1 },
  { name: "idx_orders_status_created_desc" }
);

// Index: filter by customer_city (admin stats by city)
db.orders.createIndex(
  { "customer_city": 1 },
  { name: "idx_orders_customer_city" }
);

// Index: filter by user_id (list orders per user)
db.orders.createIndex(
  { "user_id": 1, "created_at": -1 },
  { name: "idx_orders_user_id_created" }
);

// ── products collection ────────────────────────────────────────────
// Compound index: is_active + sort newest (default list_products)
db.products.createIndex(
  { "is_active": 1, "created_at": -1 },
  { name: "idx_products_active_created_desc" }
);

// Compound index: is_active + category (filter by category)
db.products.createIndex(
  { "is_active": 1, "category": 1 },
  { name: "idx_products_active_category" }
);

// Compound index: is_active + price (sort by price_asc/desc)
db.products.createIndex(
  { "is_active": 1, "price": 1 },
  { name: "idx_products_active_price" }
);

// Compound index: is_active + rating (sort by rating)
db.products.createIndex(
  { "is_active": 1, "rating": -1 },
  { name: "idx_products_active_rating_desc" }
);

// ── users collection ───────────────────────────────────────────────
// Index unik: email (login, register — query paling sering)
db.users.createIndex(
  { "email": 1 },
  { unique: true, name: "idx_users_email_unique" }
);

// Index: role (filter admin vs user)
db.users.createIndex(
  { "role": 1 },
  { name: "idx_users_role" }
);

// Compound index: role + is_active (admin_list_users dengan filter)
db.users.createIndex(
  { "role": 1, "is_active": 1 },
  { name: "idx_users_role_active" }
);

// ── audit_logs collection ──────────────────────────────────────────
// Index: sort by created_at (admin_logs — list terbaru)
db.audit_logs.createIndex(
  { "created_at": -1 },
  { name: "idx_logs_created_at_desc" }
);

// Compound index: admin_id + created_at (filter log per admin)
db.audit_logs.createIndex(
  { "admin_id": 1, "created_at": -1 },
  { name: "idx_logs_admin_id_created" }
);

print("");
print("✅ [init-indexes] Semua index berhasil dibuat:");
print("  orders    : " + db.orders.getIndexes().length + " indexes");
print("  products  : " + db.products.getIndexes().length + " indexes");
print("  users     : " + db.users.getIndexes().length + " indexes");
print("  audit_logs: " + db.audit_logs.getIndexes().length + " indexes");
print("");
