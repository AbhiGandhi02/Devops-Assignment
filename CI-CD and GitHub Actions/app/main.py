"""Orbit Tasks - a tiny task-list API used to demonstrate CI/CD with GitHub Actions."""
import os
import platform
from datetime import datetime, timezone

from flask import Flask, jsonify, request

APP_VERSION = os.environ.get("APP_VERSION", "dev")


def create_app():
    app = Flask(__name__)
    tasks = {}
    counter = {"next_id": 1}

    @app.get("/")
    def index():
        return jsonify(
            app="orbit-tasks",
            author="Abhi Gandhi",
            version=APP_VERSION,
            message="Hello from the Session 16 CI/CD pipeline",
        )

    @app.get("/health")
    def health():
        return jsonify(status="ok", time=datetime.now(timezone.utc).isoformat(), python=platform.python_version())

    @app.get("/tasks")
    def list_tasks():
        return jsonify(sorted(tasks.values(), key=lambda t: t["id"]))

    @app.post("/tasks")
    def create_task():
        body = request.get_json(silent=True) or {}
        title = str(body.get("title", "")).strip()
        if not title:
            return jsonify(error="title is required"), 400
        if len(title) > 120:
            return jsonify(error="title must be 120 characters or fewer"), 400
        task = {"id": counter["next_id"], "title": title, "done": False}
        tasks[task["id"]] = task
        counter["next_id"] += 1
        return jsonify(task), 201

    @app.patch("/tasks/<int:task_id>")
    def complete_task(task_id):
        task = tasks.get(task_id)
        if task is None:
            return jsonify(error="task not found"), 404
        task["done"] = bool((request.get_json(silent=True) or {}).get("done", True))
        return jsonify(task)

    @app.delete("/tasks/<int:task_id>")
    def delete_task(task_id):
        if tasks.pop(task_id, None) is None:
            return jsonify(error="task not found"), 404
        return "", 204

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
