import os
from flask import Flask, jsonify, request
from flask_cors import CORS
from db import db
from dotenv import load_dotenv
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from models import TaskModel


app = Flask(__name__)
CORS(app)
load_dotenv()

DB_HOST = os.environ["DB_HOST"]
DB_NAME = os.environ["DB_NAME"]
DB_USERNAME = os.environ["DB_USERNAME"]
DB_PASSWORD = os.environ["DB_PASSWORD"]

app.config["SQLALCHEMY_DATABASE_URI"] = f"postgresql://{DB_USERNAME}:{DB_PASSWORD}@{DB_HOST}/{DB_NAME}"
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db.init_app(app)
migrate = Migrate(app, db)

@app.route("/tasks", methods=["GET"])
def get_tasks():
    tasks = TaskModel.query.order_by(TaskModel.id).all()
    task_list = [{"id": t.id, "task": t.task} for t in tasks]

    return jsonify(task_list), 200

@app.route("/tasks", methods=["POST"])
def create_task():
    data = request.get_json()
    task_text = data.get("task")

    if not task_text:
        return jsonify({"error": "Task is required"}), 400

    new_task = TaskModel(task=task_text)
    db.session.add(new_task)
    db.session.commit()

    return jsonify({"message": "Your task has been added!"}), 201

@app.route("/health", methods=["GET"])
def get_health():
    return {"status": "ok"}, 200
