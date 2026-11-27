import 'package:sqlite3/sqlite3.dart';

/// Opens the shop's local SQLite database and keeps its tables up to date.
///
/// The database on the counter PC is the source of truth, so billing works
/// without internet. Cloud sync is added in a later phase.
class AppDatabase {
  AppDatabase._(this.db) {
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA journal_mode = WAL;');
    _migrate();
  }

  factory AppDatabase.open(String path) => AppDatabase._(sqlite3.open(path));
  factory AppDatabase.inMemory() => AppDatabase._(sqlite3.openInMemory());

  final Database db;

  static const _schemaVersion = 6;

  void _migrate() {
    final v = db.userVersion;
    if (v < 1) {
      db.execute('''
CREATE TABLE products (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name_en TEXT NOT NULL,
  name_ta TEXT NOT NULL DEFAULT '',
  name_tanglish TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT '',
  brand TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  barcode TEXT,
  purchase_price REAL NOT NULL DEFAULT 0,
  selling_price REAL NOT NULL DEFAULT 0,
  min_stock REAL NOT NULL DEFAULT 0,
  stock_unit TEXT NOT NULL,
  stock_qty REAL NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX idx_products_barcode ON products(barcode);

CREATE TABLE product_variants (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  unit TEXT NOT NULL,
  quantity REAL NOT NULL,
  stock_factor REAL NOT NULL,
  selling_price REAL NOT NULL,
  purchase_price REAL NOT NULL DEFAULT 0,
  barcode TEXT,
  is_default INTEGER NOT NULL DEFAULT 0,
  sort INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_variants_product ON product_variants(product_id);
CREATE INDEX idx_variants_barcode ON product_variants(barcode);

-- Spoken phrases the owner has corrected, so voice learns each shop's words.
CREATE TABLE voice_aliases (
  phrase_key TEXT PRIMARY KEY,
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  hits INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL
);

CREATE TABLE sales (
  id TEXT PRIMARY KEY,
  bill_no INTEGER NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  total REAL NOT NULL,
  payment_mode TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PAID'
);

CREATE TABLE sale_items (
  id TEXT PRIMARY KEY,
  sale_id TEXT NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL REFERENCES products(id),
  variant_id TEXT REFERENCES product_variants(id),
  count REAL NOT NULL,
  unit_price REAL NOT NULL,
  line_total REAL NOT NULL,
  stock_delta REAL NOT NULL,
  entered_by TEXT NOT NULL,
  spoken_text TEXT
);

-- Every change to stock, so stock can always be explained and rebuilt.
CREATE TABLE stock_movements (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL REFERENCES products(id),
  delta REAL NOT NULL,
  type TEXT NOT NULL,
  ref_id TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_movements_product ON stock_movements(product_id);
''');
    }
    if (v < 2) {
      db.execute('''
-- Every phrase heard by voice, what it became, and whether the owner had to
-- fix it. Used to judge how well the speech service handles Tanglish.
CREATE TABLE voice_log (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  service TEXT NOT NULL,
  heard TEXT NOT NULL,
  alternatives TEXT NOT NULL DEFAULT '',
  used_text TEXT NOT NULL,
  sure_items INTEGER NOT NULL DEFAULT 0,
  unsure_items INTEGER NOT NULL DEFAULT 0,
  result TEXT NOT NULL DEFAULT ''
);
''');
    }
    if (v < 3) {
      db.execute('''
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  role TEXT NOT NULL,
  pin_hash TEXT NOT NULL,
  pin_salt TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE suppliers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  gstin TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  balance REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE purchases (
  id TEXT PRIMARY KEY,
  supplier_id TEXT NOT NULL REFERENCES suppliers(id),
  invoice_no TEXT NOT NULL DEFAULT '',
  invoice_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  total REAL NOT NULL,
  paid REAL NOT NULL DEFAULT 0,
  source TEXT NOT NULL DEFAULT 'MANUAL',
  image_path TEXT,
  user_id TEXT
);

CREATE TABLE purchase_items (
  id TEXT PRIMARY KEY,
  purchase_id TEXT NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL REFERENCES products(id),
  variant_id TEXT REFERENCES product_variants(id),
  count REAL NOT NULL,
  unit_cost REAL NOT NULL,
  gst_percent REAL NOT NULL DEFAULT 0,
  line_total REAL NOT NULL,
  stock_delta REAL NOT NULL
);

CREATE TABLE supplier_payments (
  id TEXT PRIMARY KEY,
  supplier_id TEXT NOT NULL REFERENCES suppliers(id),
  amount REAL NOT NULL,
  mode TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);

ALTER TABLE sales ADD COLUMN user_id TEXT;
ALTER TABLE sale_items ADD COLUMN cost_total REAL NOT NULL DEFAULT 0;
ALTER TABLE stock_movements ADD COLUMN note TEXT NOT NULL DEFAULT '';
ALTER TABLE stock_movements ADD COLUMN user_id TEXT;
CREATE INDEX idx_sales_created ON sales(created_at);
CREATE INDEX idx_purchases_created ON purchases(invoice_date);
''');
    }
    if (v < 4) {
      // Customer credit book (kadan), bill discount and shop expenses.
      db.execute('''
CREATE TABLE customers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  balance REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE customer_payments (
  id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL REFERENCES customers(id),
  amount REAL NOT NULL,
  mode TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  user_id TEXT
);

CREATE TABLE expenses (
  id TEXT PRIMARY KEY,
  day TEXT NOT NULL,
  category TEXT NOT NULL,
  amount REAL NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  user_id TEXT
);
CREATE INDEX idx_expenses_day ON expenses(day);

ALTER TABLE sales ADD COLUMN customer_id TEXT;
ALTER TABLE sales ADD COLUMN discount REAL NOT NULL DEFAULT 0;
CREATE INDEX idx_sales_customer ON sales(customer_id);
''');
    }
    if (v < 5) {
      // Wholesale prices and wholesale customers.
      db.execute('''
ALTER TABLE products ADD COLUMN wholesale_price REAL NOT NULL DEFAULT 0;
ALTER TABLE product_variants ADD COLUMN wholesale_price REAL NOT NULL DEFAULT 0;
ALTER TABLE customers ADD COLUMN is_wholesale INTEGER NOT NULL DEFAULT 0;
ALTER TABLE sales ADD COLUMN wholesale INTEGER NOT NULL DEFAULT 0;
''');
    }
    if (v < 6) {
      // Staff phones that bill through the shop PC.
      db.execute('''
-- On the PC: phones allowed to send bills.
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  token TEXT NOT NULL,
  paired_at TEXT NOT NULL,
  last_seen TEXT,
  active INTEGER NOT NULL DEFAULT 1
);

-- On a phone: bills and changes still to be sent to the PC.
CREATE TABLE sync_outbox (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  ref_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  tries INTEGER NOT NULL DEFAULT 0,
  last_error TEXT NOT NULL DEFAULT ''
);

-- Which phone made a bill, and its number there.
ALTER TABLE sales ADD COLUMN device_id TEXT;
ALTER TABLE sales ADD COLUMN device_bill_no INTEGER;
-- On a phone: the PC's number for the bill once it is sent.
ALTER TABLE sales ADD COLUMN pc_bill_no INTEGER;
''');
    }
    db.userVersion = _schemaVersion;
  }

  void close() => db.close();
}
