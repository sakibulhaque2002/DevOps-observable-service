"""FastAPI application, bounded metric labels, and JSON request logs."""

import hmac
import json
import logging
import os
import time
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import UTC, datetime

from fastapi import FastAPI, Header, HTTPException
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Histogram,
    generate_latest,
)
from starlette.responses import Response
from starlette.types import ASGIApp, Message, Receive, Scope, Send


@dataclass(frozen=True)
class Settings:
    port: int = 8080
    log_level: str = "INFO"
    environment: str = "local"
    version: str = "1.0.0"
    enable_demo_endpoints: bool = False
    demo_token: str = ""

    @classmethod
    def from_env(cls) -> "Settings":
        settings = cls(
            port=int(os.getenv("PORT", "8080")),
            log_level=os.getenv("LOG_LEVEL", "INFO").upper(),
            environment=os.getenv("ENVIRONMENT", "local"),
            version=os.getenv("APP_VERSION", "1.0.0"),
            enable_demo_endpoints=os.getenv("ENABLE_DEMO_ENDPOINTS", "false").lower() == "true",
            demo_token=os.getenv("DEMO_TOKEN", ""),
        )
        if not 1 <= settings.port <= 65535:
            raise ValueError("PORT must be between 1 and 65535")
        if settings.log_level not in {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}:
            raise ValueError("LOG_LEVEL must be a Python logging level")
        if settings.enable_demo_endpoints and not settings.demo_token:
            raise ValueError("DEMO_TOKEN is required when demo endpoints are enabled")
        return settings


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname.lower(),
            "message": record.getMessage(),
        }
        payload.update(getattr(record, "fields", {}))
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload)


def configure_logging(level: str) -> logging.Logger:
    import sys

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level)
    return logging.getLogger("service")


class ObservabilityMiddleware:
    def __init__(
        self,
        app: ASGIApp,
        requests: Counter,
        errors: Counter,
        latency: Histogram,
        logger: logging.Logger,
        settings: Settings,
    ) -> None:
        self.app, self.requests, self.errors, self.latency = app, requests, errors, latency
        self.logger, self.settings = logger, settings

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        started, status = time.perf_counter(), 500

        async def capture(message: Message) -> None:
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, capture)
        except Exception:
            self.logger.exception("Unhandled request exception")
            raise
        finally:
            elapsed = time.perf_counter() - started
            route = scope.get("route")
            path = getattr(route, "path", "__unmatched__")
            method = scope["method"]
            if method not in {"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"}:
                method = "OTHER"
            if path != "/metrics":
                self.requests.labels(method, path, str(status)).inc()
                self.latency.labels(method, path).observe(elapsed)
                if status >= 400:
                    self.errors.labels(method, path, str(status)).inc()
            self.logger.log(
                logging.ERROR if status >= 500 else logging.INFO,
                "HTTP request completed",
                extra={
                    "fields": {
                        "method": method,
                        "path": path,
                        "status": status,
                        "duration_seconds": round(elapsed, 6),
                        "environment": self.settings.environment,
                        "version": self.settings.version,
                    }
                },
            )


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    logger = configure_logging(settings.log_level)
    registry = CollectorRegistry()
    labels = ["method", "path", "status"]
    requests = Counter("http_requests_total", "Completed HTTP requests", labels, registry=registry)
    errors = Counter(
        "http_errors_total", "HTTP responses with status >= 400", labels, registry=registry
    )
    latency = Histogram(
        "http_request_duration_seconds",
        "Request latency in seconds",
        ["method", "path"],
        buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
        registry=registry,
    )

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        logger.info("Service started", extra={"fields": {"environment": settings.environment}})
        yield
        logger.info("Service stopped gracefully")

    app = FastAPI(title="DevOps Observable Service", version=settings.version, lifespan=lifespan)
    app.add_middleware(
        ObservabilityMiddleware,
        requests=requests,
        errors=errors,
        latency=latency,
        logger=logger,
        settings=settings,
    )

    @app.get("/")
    async def index():
        return {
            "message": "Hello from DevOps Task!",
            "status": "running",
            "version": settings.version,
        }

    @app.get("/health")
    async def health():
        return {"status": "healthy"}

    @app.get("/metrics", include_in_schema=False)
    async def metrics():
        return Response(generate_latest(registry), headers={"Content-Type": CONTENT_TYPE_LATEST})

    if settings.enable_demo_endpoints:

        @app.get("/demo/error", include_in_schema=False)
        async def demo_error(x_demo_token: str = Header(default="")):
            if not hmac.compare_digest(x_demo_token, settings.demo_token):
                raise HTTPException(status_code=403, detail="Invalid demo token")
            raise HTTPException(
                status_code=503, detail="Intentional failure for observability demo"
            )

    return app
