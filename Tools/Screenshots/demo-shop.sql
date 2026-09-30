-- A made-up shop, for screenshots. Every name, address and figure here is invented.
PRAGMA foreign_keys = ON;

CREATE TABLE customers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  city TEXT NOT NULL,
  joined_on TEXT NOT NULL
);

CREATE TABLE products (
  id INTEGER PRIMARY KEY,
  sku TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  price_cents INTEGER NOT NULL,
  in_stock INTEGER NOT NULL
);

CREATE TABLE orders (
  id INTEGER PRIMARY KEY,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  placed_at TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending','paid','shipped','delivered','refunded')),
  total_cents INTEGER NOT NULL
);

CREATE TABLE order_items (
  order_id INTEGER NOT NULL REFERENCES orders(id),
  product_id INTEGER NOT NULL REFERENCES products(id),
  quantity INTEGER NOT NULL,
  PRIMARY KEY (order_id, product_id)
);

CREATE INDEX orders_by_customer ON orders(customer_id);
CREATE INDEX orders_by_status ON orders(status);

-- The rest of the shop, for the schema diagram: empty, but every key is real.
CREATE TABLE categories (
  id INTEGER PRIMARY KEY,
  parent_id INTEGER REFERENCES categories(id),
  name TEXT NOT NULL
);

CREATE TABLE addresses (
  id INTEGER PRIMARY KEY,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  line1 TEXT NOT NULL,
  city TEXT NOT NULL,
  postcode TEXT NOT NULL
);

CREATE TABLE payments (
  id INTEGER PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders(id),
  method TEXT NOT NULL,
  amount_cents INTEGER NOT NULL,
  paid_at TEXT
);

CREATE TABLE shipments (
  id INTEGER PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders(id),
  address_id INTEGER NOT NULL REFERENCES addresses(id),
  carrier TEXT NOT NULL,
  shipped_at TEXT
);

CREATE TABLE suppliers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  country TEXT NOT NULL
);

CREATE TABLE product_suppliers (
  product_id INTEGER NOT NULL REFERENCES products(id),
  supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
  cost_cents INTEGER NOT NULL,
  PRIMARY KEY (product_id, supplier_id)
);

CREATE TABLE reviews (
  id INTEGER PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products(id),
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  stars INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
  body TEXT
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT
);
