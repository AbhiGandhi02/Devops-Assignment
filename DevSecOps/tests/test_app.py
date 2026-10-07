import pytest

from app.main import create_app

TOKEN = "unit-test-token"


@pytest.fixture()
def client():
    return create_app(api_token=TOKEN).test_client()


def auth():
    return {"X-API-Token": TOKEN}


def test_index_and_health(client):
    assert client.get("/").get_json()["app"] == "orbit-vault"
    assert client.get("/health").get_json()["status"] == "ok"


def test_security_headers_present(client):
    resp = client.get("/")
    assert resp.headers["X-Content-Type-Options"] == "nosniff"
    assert resp.headers["X-Frame-Options"] == "DENY"
    assert "default-src 'none'" in resp.headers["Content-Security-Policy"]


@pytest.mark.parametrize("headers", [{}, {"X-API-Token": "wrong"}])
def test_notes_require_valid_token(client, headers):
    assert client.get("/notes", headers=headers).status_code == 401
    assert client.post("/notes", json={"title": "a", "text": "b"}, headers=headers).status_code == 401


def test_empty_server_token_rejects_everyone():
    c = create_app(api_token="").test_client()
    assert c.get("/notes", headers={"X-API-Token": ""}).status_code == 401


def test_create_and_list_note(client):
    resp = client.post("/notes", json={"title": "Release 1.0", "text": "ship it"}, headers=auth())
    assert resp.status_code == 201
    assert client.get("/notes", headers=auth()).get_json() == [{"id": 1, "title": "Release 1.0", "text": "ship it"}]


@pytest.mark.parametrize("payload", [
    {"title": "<script>alert(1)</script>", "text": "xss"},
    {"title": "", "text": "x"},
    {"title": "ok", "text": ""},
    {"title": "ok", "text": "x" * 501},
])
def test_input_validation(client, payload):
    assert client.post("/notes", json=payload, headers=auth()).status_code == 400
