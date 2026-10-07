"""Prometheus metrics exposed on /metrics."""
from prometheus_client import Counter, Gauge, Histogram

REQUESTS = Counter(
    "readtrack_http_requests_total", "HTTP requests handled", ["method", "path", "status"]
)
LATENCY = Histogram(
    "readtrack_http_request_duration_seconds", "HTTP request latency", ["method", "path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5),
)
BOOKS_CREATED = Counter("readtrack_books_created_total", "Books added through the API")
BOOKS_DELETED = Counter("readtrack_books_deleted_total", "Books deleted through the API")
DB_UP = Gauge("readtrack_db_up", "1 if the last readiness check reached the database")
APP_INFO = Gauge("readtrack_app_info", "Build information", ["version", "env"])
