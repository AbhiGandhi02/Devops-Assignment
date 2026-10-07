import pytest

from app.main import create_app


@pytest.fixture()
def client():
    return create_app().test_client()


def test_index_identifies_app(client):
    body = client.get("/").get_json()
    assert body["app"] == "orbit-tasks"
    assert body["author"] == "Abhi Gandhi"


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_create_and_list_tasks(client):
    assert client.get("/tasks").get_json() == []
    resp = client.post("/tasks", json={"title": "write Dockerfile"})
    assert resp.status_code == 201
    assert resp.get_json() == {"id": 1, "title": "write Dockerfile", "done": False}
    client.post("/tasks", json={"title": "push to GHCR"})
    titles = [t["title"] for t in client.get("/tasks").get_json()]
    assert titles == ["write Dockerfile", "push to GHCR"]


@pytest.mark.parametrize("payload", [{}, {"title": "   "}, {"title": "x" * 121}])
def test_create_task_validation(client, payload):
    resp = client.post("/tasks", json=payload)
    assert resp.status_code == 400
    assert "error" in resp.get_json()


def test_complete_task(client):
    client.post("/tasks", json={"title": "run tests"})
    resp = client.patch("/tasks/1", json={"done": True})
    assert resp.status_code == 200
    assert resp.get_json()["done"] is True


def test_missing_task_returns_404(client):
    assert client.patch("/tasks/99", json={"done": True}).status_code == 404
    assert client.delete("/tasks/99").status_code == 404


def test_delete_task(client):
    client.post("/tasks", json={"title": "temporary"})
    assert client.delete("/tasks/1").status_code == 204
    assert client.get("/tasks").get_json() == []
