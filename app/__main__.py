"""Uvicorn handles SIGTERM and drains requests within the container stop timeout."""

import uvicorn

from app.main import JSONFormatter, Settings, create_app


def main() -> None:
    settings = Settings.from_env()
    uvicorn.run(
        create_app(settings),
        host="0.0.0.0",
        port=settings.port,
        log_level=settings.log_level.lower(),
        access_log=False,
        timeout_graceful_shutdown=20,
        log_config={
            "version": 1,
            "disable_existing_loggers": False,
            "formatters": {"json": {"()": JSONFormatter}},
            "handlers": {
                "stdout": {
                    "class": "logging.StreamHandler",
                    "stream": "ext://sys.stdout",
                    "formatter": "json",
                }
            },
            "root": {"handlers": ["stdout"], "level": settings.log_level},
        },
    )


if __name__ == "__main__":
    main()
