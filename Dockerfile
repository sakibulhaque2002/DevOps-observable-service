# syntax=docker/dockerfile:1
FROM python:3.15.0-alpine3.24@sha256:2699b90f4d562a22e2dd076c82f964032f64814204bff36d271a54ba4cc2c7e2 AS builder
WORKDIR /build
COPY requirements.txt .
RUN python -m pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

FROM python:3.15.0-alpine3.24@sha256:2699b90f4d562a22e2dd076c82f964032f64814204bff36d271a54ba4cc2c7e2 AS runtime
ARG VERSION=1.0.0
ARG REVISION=unknown
LABEL org.opencontainers.image.title="DevOps Observable Service" \
      org.opencontainers.image.description="Observable Python FastAPI assessment service" \
      org.opencontainers.image.source="https://github.com/sakibulhaque2002/DevOps-observable-service" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}"
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080 \
    LOG_LEVEL=INFO \
    ENVIRONMENT=production \
    APP_VERSION=${VERSION}
RUN addgroup -g 10001 app && adduser -D -H -u 10001 -G app app
WORKDIR /app
RUN --mount=type=bind,from=builder,source=/wheels,target=/wheels \
    python -m pip install --no-cache-dir --no-compile --no-index /wheels/*.whl
COPY --chown=10001:10001 app/ ./app/
USER 10001:10001
EXPOSE 8080
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import os,urllib.request; urllib.request.urlopen('http://127.0.0.1:'+os.getenv('PORT','8080')+'/health',timeout=2)" || exit 1
CMD ["python", "-m", "app"]
