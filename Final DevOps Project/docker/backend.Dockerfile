# ReadTrack backend - multi-stage, non-root FastAPI image.
# build: docker build -f docker/backend.Dockerfile -t readtrack-backend application/backend
FROM python:3.12-slim AS build
WORKDIR /src
COPY requirements.txt .
RUN python -m venv /venv && /venv/bin/pip install --no-cache-dir -r requirements.txt \
    && /venv/bin/pip uninstall -y pip

FROM python:3.12-slim
ARG APP_VERSION=dev
LABEL org.opencontainers.image.source="https://github.com/AbhiGandhi02/Devops-Assignment" \
      org.opencontainers.image.description="ReadTrack API (FastAPI) - Final DevOps Project"
ENV PATH="/venv/bin:$PATH" APP_VERSION=$APP_VERSION PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
# pip is not needed at runtime and its vendored urllib3/msgpack/setuptools carried HIGH CVEs
# (found by Trivy) - so it is removed from the final image together with the OS upgrades.
RUN apt-get update && apt-get upgrade -y --no-install-recommends && rm -rf /var/lib/apt/lists/* \
    && python -m pip uninstall -y --root-user-action=ignore pip \
    && useradd --create-home --uid 10001 readtrack
WORKDIR /app
COPY --from=build /venv /venv
COPY alembic.ini ./
COPY alembic ./alembic
COPY app ./app
USER 10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--no-access-log"]
