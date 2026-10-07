"""Orbit Vault - a small notes API built to go through a DevSecOps pipeline."""
import hmac
import os
import re
from datetime import datetime, timezone

from flask import Flask, abort, jsonify, request

APP_VERSION = os.environ.get("APP_VERSION", "dev")
TITLE_RE = re.compile(r"^[\w .,:!?'-]{1,80}$")


def create_app(api_token=None):
    app = Flask(__name__)
    # The token comes from a Kubernetes Secret at runtime - never from source code.
    token = api_token if api_token is not None else os.environ.get("VAULT_API_TOKEN", "")
    notes = []

    def require_token():
        sent = request.headers.get("X-API-Token", "")
        # constant-time comparison avoids timing attacks
        if not token or not hmac.compare_digest(sent, token):
            abort(401)

    @app.after_request
    def security_headers(resp):
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["X-Frame-Options"] = "DENY"
        resp.headers["Content-Security-Policy"] = "default-src 'none'"
        resp.headers["Cache-Control"] = "no-store"
        return resp

    @app.errorhandler(401)
    def unauthorized(_):
        return jsonify(error="missing or invalid X-API-Token"), 401

    @app.get("/")
    def index():
        return jsonify(app="orbit-vault", author="Abhi Gandhi", version=APP_VERSION)

    @app.get("/health")
    def health():
        return jsonify(status="ok", time=datetime.now(timezone.utc).isoformat())

    @app.get("/notes")
    def list_notes():
        require_token()
        return jsonify(notes)

    @app.post("/notes")
    def add_note():
        require_token()
        body = request.get_json(silent=True) or {}
        title = str(body.get("title", "")).strip()
        text = str(body.get("text", "")).strip()
        if not TITLE_RE.match(title):
            return jsonify(error="title must be 1-80 plain characters"), 400
        if not text or len(text) > 500:
            return jsonify(error="text must be 1-500 characters"), 400
        note = {"id": len(notes) + 1, "title": title, "text": text}
        notes.append(note)
        return jsonify(note), 201

    return app


app = create_app()

if __name__ == "__main__":
    # Bind address comes from the environment; default is localhost only.
    app.run(host=os.environ.get("BIND_HOST", "127.0.0.1"), port=8000)
