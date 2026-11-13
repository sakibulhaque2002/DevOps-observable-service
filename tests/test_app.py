import json
import logging

import pytest
from fastapi.testclient import TestClient

from app.main import JSONFormatter, Settings, create_app


@pytest.fixture
def client():
    with TestClient(create_app(Settings(version="2.3.4"))) as instance:
        yield instance


def test_index(client):
    assert client.get("/").json() == {
        "message": "Hello from DevOps Task!",
        "status": "running",
        "version": "2.3.4",
    }


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_metrics_count_errors_and_bound_unknown_paths(client):
    client.get("/")
    client.get("/unknown/private-value")
    client.get("/different-private-value")
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "text/plain" in response.headers["content-type"]
    assert 'http_requests_total{method="GET",path="/",status="200"} 1.0' in response.text
    assert 'http_errors_total{method="GET",path="__unmatched__",status="404"} 2.0' in response.text
    assert "http_request_duration_seconds_bucket" in response.text
    assert "private-value" not in response.text


def test_metrics_do_not_measure_their_own_scrapes(client):
    first = client.get("/metrics").text
    assert client.get("/metrics").text == first


def test_demo_disabled_by_default(client):
    assert client.get("/demo/error").status_code == 404


def test_demo_requires_token_and_records_5xx():
    with TestClient(create_app(Settings(enable_demo_endpoints=True, demo_token="test-only"))) as c:
        assert c.get("/demo/error").status_code == 403
        assert c.get("/demo/error", headers={"X-Demo-Token": "test-only"}).status_code == 503
        assert 'path="/demo/error",status="503"} 1.0' in c.get("/metrics").text


def test_settings_read_environment(monkeypatch):
    for key, value in {
        "PORT": "9090",
        "LOG_LEVEL": "debug",
        "ENVIRONMENT": "staging",
        "APP_VERSION": "2.0.0",
        "ENABLE_DEMO_ENDPOINTS": "true",
        "DEMO_TOKEN": "test-only",
    }.items():
        monkeypatch.setenv(key, value)
    settings = Settings.from_env()
    assert (settings.port, settings.log_level, settings.environment, settings.version) == (
        9090,
        "DEBUG",
        "staging",
        "2.0.0",
    )
    assert settings.enable_demo_endpoints


@pytest.mark.parametrize(
    "key,value",
    [("PORT", "0"), ("PORT", "65536"), ("LOG_LEVEL", "invalid"), ("ENABLE_DEMO_ENDPOINTS", "true")],
)
def test_invalid_configuration_fails_early(monkeypatch, key, value):
    monkeypatch.delenv("DEMO_TOKEN", raising=False)
    monkeypatch.setenv(key, value)
    with pytest.raises(ValueError):
        Settings.from_env()


def test_json_log_format():
    record = logging.LogRecord("test", logging.INFO, "", 0, "hello", (), None)
    record.fields = {"path": "/", "status": 200}
    result = json.loads(JSONFormatter().format(record))
    assert result["message"] == "hello"
    assert result["path"] == "/"
    assert result["level"] == "info"
    assert result["timestamp"]
