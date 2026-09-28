#!/usr/bin/env python3
"""Builds the made-up shop database the screenshots use: demo-shop.sql's schema, filled with invented
customers, products and orders from a fixed seed, so every run produces the same file.

    Tools/Screenshots/make-demo-db.py <output.sqlite>
"""
import os
import random
import sqlite3
import sys
from pathlib import Path

out = Path(sys.argv[1] if len(sys.argv) > 1 else "demo-shop.sqlite")
random.seed(27)
if out.exists():
    out.unlink()
db = sqlite3.connect(out)
db.executescript((Path(__file__).parent / "demo-shop.sql").read_text())
first = ["Ann", "Ben", "Cara", "Dev", "Eli", "Fay", "Gus", "Hana", "Ivo", "Jun", "Kai", "Lena", "Milo",
         "Nia", "Otto", "Pia", "Quin", "Rae", "Sol", "Tess"]
last = ["Abbott", "Brook", "Castillo", "Dahl", "Ekwueme", "Fischer", "Garza", "Holm", "Ito", "Jansen",
        "Kowal", "Lund", "Moreau", "Novak", "Okafor", "Park", "Quist", "Rossi", "Silva", "Tan"]
cities = ["Lisbon", "Osaka", "Denver", "Oslo", "Austin", "Porto", "Kyoto", "Tallinn", "Halifax", "Perth"]
for i in range(1, 241):
    f, l = random.choice(first), random.choice(last)
    db.execute("insert into customers values (?,?,?,?,?)",
               (i, f"{f} {l}", f"{f.lower()}.{l.lower()}{i}@example.com", random.choice(cities),
                f"2025-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}"))
categories = {"Keyboards": ["Split Keyboard", "Low-Profile Keyboard", "Keycap Set"],
              "Cables": ["USB-C Cable 2 m", "Thunderbolt Cable", "Braided USB-C Cable"],
              "Stands": ["Laptop Stand", "Monitor Arm", "Headset Stand"],
              "Audio": ["Studio Headphones", "USB Microphone", "Desk Speakers"],
              "Storage": ["NVMe Enclosure", "2 TB SSD", "SD Card Reader"]}
product = 1
for category, names in categories.items():
    for name in names:
        db.execute("insert into products values (?,?,?,?,?,?)",
                   (product, f"GPT-{product:04d}", name, category,
                    random.choice([1299, 2499, 3999, 5999, 8999, 12999, 19999]), random.randint(0, 140)))
        product += 1
statuses = ["pending", "paid", "shipped", "delivered", "delivered", "delivered", "refunded"]
for order in range(1, 1201):
    db.execute("insert into orders values (?,?,?,?,0)",
               (order, random.randint(1, 240),
                f"2026-{random.randint(1, 9):02d}-{random.randint(1, 28):02d} "
                f"{random.randint(8, 21):02d}:{random.randint(0, 59):02d}", random.choice(statuses)))
    total = 0
    for item in random.sample(range(1, product), random.randint(1, 3)):
        quantity = random.randint(1, 3)
        price = db.execute("select price_cents from products where id = ?", (item,)).fetchone()[0]
        total += quantity * price
        db.execute("insert into order_items values (?,?,?)", (order, item, quantity))
    db.execute("update orders set total_cents = ? where id = ?", (total, order))
db.commit()
db.execute("vacuum")
db.close()
print(f"make-demo-db: {out} ({os.path.getsize(out)} bytes)")
