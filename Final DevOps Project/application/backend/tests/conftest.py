"""Test fixtures: every test gets a fresh in-memory SQLite database, so the
tests never touch the PostgreSQL database used by compose or Kubernetes."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import Base, get_db
from app.main import app


@pytest.fixture()
def client():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    TestingSession = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

    def override_get_db():
        db = TestingSession()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
    engine.dispose()


@pytest.fixture()
def book(client):
    r = client.post(
        "/api/books",
        json={"title": "The Pragmatic Programmer", "author": "Hunt & Thomas", "status": "reading", "pages": 352},
    )
    assert r.status_code == 201
    return r.json()
