import os
from flask import Flask, jsonify, request
from flask_cors import CORS
import psycopg2
from psycopg2.extras import RealDictCursor

app = Flask(__name__)
CORS(app)

def get_connection():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        database=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        cursor_factory=RealDictCursor
    )


@app.route("/tasks", methods=["GET"])
def get_tasks():
    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT id, title FROM tasks ORDER BY id;")
    tasks = cur.fetchall()

    cur.close()
    conn.close()

    return jsonify(tasks), 200

@app.route("/tasks", methods=["POST"])
def create_task():
    data = request.get_json()

    title = data.get("title")

    if not title:
        return jsonify({"error": "Title is required"}), 400

    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        "INSERT INTO tasks (title) VALUES (%s) RETURNING id, title;",
        (title)
    )

    task_id = cur.fetchone()["id"]
    conn.commit()

    cur.close()
    conn.close()

    return jsonify({
        "id": task_id,
        "title": title
    }), 201



if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)