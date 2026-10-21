"""Print live row counts for all six tables.

This script is the single source of truth for the "Live row counts" table in
docs/02-DATABASE.md. Run it after any harvest or SQL apply and paste the
output into that table — do not hand-maintain counts anywhere else. Every
other doc should link to docs/02-DATABASE.md instead of restating numbers.
"""
import os
from dotenv import load_dotenv
import mysql.connector

load_dotenv()

# All six tables defined in schema.sql, in dependency order.
TABLES = ["moods", "genres", "mood_genre_mapping", "items", "item_genres", "feedback"]

conn = mysql.connector.connect(
    host=os.getenv("DB_HOST"),
    port=int(os.getenv("DB_PORT")),
    user=os.getenv("DB_USER"),
    password=os.getenv("DB_PASSWORD"),
    database=os.getenv("DB_NAME"),
    ssl_ca=os.getenv("DB_SSL_CA"),
    ssl_verify_cert=True
)

cursor = conn.cursor()

print("# Live row counts — paste this into docs/02-DATABASE.md")
for table in TABLES:
    # Table names come from the fixed TABLES list above, never user input.
    cursor.execute(f"SELECT COUNT(*) FROM {table}")
    count = cursor.fetchone()[0]
    print(f"{table}: {count} rows")

cursor.close()
conn.close()