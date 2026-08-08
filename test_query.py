import os
from dotenv import load_dotenv
import mysql.connector

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



cursor.execute("""SELECT items.title , items.media_type , items.popularity_score , mood_genre_mapping.relevance_score 
FROM moods
JOIN mood_genre_mapping ON moods.id = mood_genre_mapping.mood_id
JOIN item_genres ON mood_genre_mapping.genre_id = item_genres.genre_id
JOIN items ON item_genres.item_id = items.id
WHERE moods.name = %s
ORDER BY mood_genre_mapping.relevance_score DESC , items.popularity_score DESC 
""", ("Happy/Excitement",))
rows = cursor.fetchall()
print(rows)

cursor.close()
conn.close()