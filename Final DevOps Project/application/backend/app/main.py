"""ReadTrack API - a small reading-list tracker (FastAPI + PostgreSQL)."""
import json
import logging
import sys
import time

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from . import metrics
from .config import get_settings
from .db import get_db, ping
from .models import STATUSES, Book
from .schemas import BookIn, BookOut, BookUpdate, Stats

settings = get_settings()


class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {"ts": self.formatTime(record), "level": record.levelname, "msg": record.getMessage()}
        payload.update(getattr(record, "extra_fields", {}))
        return json.dumps(payload)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
log = logging.getLogger("readtrack")
log.handlers = [handler]
log.setLevel(settings.log_level)
log.propagate = False

app = FastAPI(title="ReadTrack API", version=settings.app_version)
metrics.APP_INFO.labels(version=settings.app_version, env=settings.app_env).set(1)


@app.middleware("http")
async def observe(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    elapsed = time.perf_counter() - start
    route = request.scope.get("route")
    path = getattr(route, "path", "unmatched")  # template, e.g. /api/books/{book_id}
    if path != "/metrics":
        metrics.REQUESTS.labels(request.method, path, str(response.status_code)).inc()
        metrics.LATENCY.labels(request.method, path).observe(elapsed)
        if path not in ("/health", "/ready"):
            log.info("request", extra={"extra_fields": {
                "method": request.method, "path": request.url.path,
                "status": response.status_code, "ms": round(elapsed * 1000, 1)}})
    return response


@app.get("/")
def root():
    return {"service": "readtrack-api", "version": settings.app_version, "docs": "/docs"}


@app.get("/health")
def health():
    """Liveness: the process is up and can answer HTTP."""
    return {"status": "ok"}


@app.get("/ready")
def ready(db: Session = Depends(get_db)):
    """Readiness: only accept traffic when the database answers."""
    try:
        ping(db)
    except Exception as exc:  # any DB error means not ready
        metrics.DB_UP.set(0)
        log.warning("readiness failed", extra={"extra_fields": {"error": type(exc).__name__}})
        raise HTTPException(status_code=503, detail="database unavailable")
    metrics.DB_UP.set(1)
    return {"status": "ready"}


@app.get("/metrics")
def prometheus_metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/info")
def info():
    return {"version": settings.app_version, "env": settings.app_env,
            "message": settings.welcome_message}


@app.get("/api/books", response_model=list[BookOut])
def list_books(status: str | None = None, db: Session = Depends(get_db)):
    query = select(Book).order_by(Book.id)
    if status:
        if status not in STATUSES:
            raise HTTPException(status_code=422, detail=f"status must be one of {STATUSES}")
        query = query.where(Book.status == status)
    return db.scalars(query).all()


@app.get("/api/books/stats", response_model=Stats)
def stats(db: Session = Depends(get_db)):
    rows = dict(db.execute(select(Book.status, func.count()).group_by(Book.status)).all())
    pages = db.scalar(select(func.coalesce(func.sum(Book.pages), 0)).where(Book.status == "finished"))
    avg = db.scalar(select(func.avg(Book.rating)).where(Book.rating.is_not(None)))
    return Stats(total=sum(rows.values()), by_status={s: rows.get(s, 0) for s in STATUSES},
                 pages_read=int(pages or 0), average_rating=round(float(avg), 2) if avg else None)


@app.get("/api/books/{book_id}", response_model=BookOut)
def get_book(book_id: int, db: Session = Depends(get_db)):
    book = db.get(Book, book_id)
    if not book:
        raise HTTPException(status_code=404, detail="book not found")
    return book


@app.post("/api/books", response_model=BookOut, status_code=201)
def create_book(payload: BookIn, db: Session = Depends(get_db)):
    book = Book(**payload.model_dump())
    db.add(book)
    db.commit()
    db.refresh(book)
    metrics.BOOKS_CREATED.inc()
    return book


@app.put("/api/books/{book_id}", response_model=BookOut)
def update_book(book_id: int, payload: BookUpdate, db: Session = Depends(get_db)):
    book = db.get(Book, book_id)
    if not book:
        raise HTTPException(status_code=404, detail="book not found")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(book, key, value)
    db.commit()
    db.refresh(book)
    return book


@app.delete("/api/books/{book_id}", status_code=204)
def delete_book(book_id: int, db: Session = Depends(get_db)):
    book = db.get(Book, book_id)
    if not book:
        raise HTTPException(status_code=404, detail="book not found")
    db.delete(book)
    db.commit()
    metrics.BOOKS_DELETED.inc()
    return Response(status_code=204)
