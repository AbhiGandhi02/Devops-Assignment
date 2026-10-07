def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_ready_checks_database(client):
    r = client.get("/ready")
    assert r.status_code == 200
    assert r.json()["status"] == "ready"


def test_create_and_get_book(client, book):
    r = client.get(f"/api/books/{book['id']}")
    assert r.status_code == 200
    assert r.json()["title"] == "The Pragmatic Programmer"
    assert r.json()["status"] == "reading"


def test_list_books_with_status_filter(client, book):
    client.post(
        "/api/books", json={"title": "Dune", "author": "Frank Herbert", "status": "finished", "pages": 612, "rating": 5}
    )
    assert len(client.get("/api/books").json()) == 2
    finished = client.get("/api/books", params={"status": "finished"}).json()
    assert [b["title"] for b in finished] == ["Dune"]
    assert client.get("/api/books", params={"status": "bogus"}).status_code == 422


def test_update_book(client, book):
    r = client.put(f"/api/books/{book['id']}", json={"status": "finished", "rating": 4})
    assert r.status_code == 200
    assert r.json()["status"] == "finished"
    assert r.json()["rating"] == 4
    assert r.json()["title"] == book["title"]  # untouched fields are kept


def test_delete_book(client, book):
    assert client.delete(f"/api/books/{book['id']}").status_code == 204
    assert client.get(f"/api/books/{book['id']}").status_code == 404
    assert client.delete(f"/api/books/{book['id']}").status_code == 404


def test_validation_rejects_bad_payload(client):
    assert client.post("/api/books", json={"title": "", "author": "x"}).status_code == 422
    assert client.post("/api/books", json={"title": "x", "author": "y", "rating": 9}).status_code == 422
    assert client.put("/api/books/999", json={"status": "reading"}).status_code == 404


def test_stats(client):
    for title, status, pages, rating in [
        ("A", "finished", 100, 4),
        ("B", "finished", 200, 5),
        ("C", "reading", 50, None),
    ]:
        client.post(
            "/api/books", json={"title": title, "author": "x", "status": status, "pages": pages, "rating": rating}
        )
    s = client.get("/api/books/stats").json()
    assert s["total"] == 3
    assert s["by_status"] == {"want_to_read": 0, "reading": 1, "finished": 2}
    assert s["pages_read"] == 300
    assert s["average_rating"] == 4.5


def test_metrics_endpoint(client, book):
    client.get("/api/books")
    body = client.get("/metrics").text
    assert "readtrack_http_requests_total" in body
    assert 'path="/api/books"' in body
    assert "readtrack_books_created_total" in body


def test_info_reads_config(client, monkeypatch):
    r = client.get("/api/info")
    assert r.status_code == 200
    assert set(r.json()) == {"version", "env", "message"}
