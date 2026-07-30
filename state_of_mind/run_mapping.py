import os
from dotenv import load_dotenv
import mysql.connector
from mysql.connector import errorcode

load_dotenv()

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

with open("mood_genre_mapping_inserts.sql", "r", encoding="utf-8") as f:
    raw_lines = f.readlines()

clean_lines = []
for line in raw_lines:
    stripped = line.strip()
    if stripped.startswith("--") or stripped == "":
        continue
    clean_lines.append(line)

sql_script = "".join(clean_lines)
statements = [s.strip() for s in sql_script.split(";") if s.strip()]

for stmt in statements:
    try:
        cursor.execute(stmt)
        print("Executed:", stmt[:60].replace("\n", " "), "...")
    except mysql.connector.Error as err:
        if err.errno == errorcode.ER_DUP_ENTRY:
            print("Skipped (duplicate):", stmt[:60].replace("\n", " "), "...")
        else:
            raise

conn.commit()
cursor.close()
conn.close()
print("mood_genre_mapping_inserts.sql applied successfully.")