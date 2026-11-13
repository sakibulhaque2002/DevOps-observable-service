from unittest.mock import patch

from app.__main__ import main


def test_startup_passes_config_and_graceful_timeout(monkeypatch):
    monkeypatch.setenv("PORT", "9091")
    monkeypatch.setenv("LOG_LEVEL", "WARNING")
    with patch("app.__main__.uvicorn.run") as run:
        main()
    assert run.call_args.kwargs["port"] == 9091
    assert run.call_args.kwargs["timeout_graceful_shutdown"] == 20
    assert run.call_args.kwargs["access_log"] is False
