"""Exercise the actual Linux collector, JSON contract, exit codes, and rotation."""

import json
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/system_health.sh"


def test_json_collection_and_warning_exit(tmp_path):
    log = tmp_path / "health_log.txt"
    result = subprocess.run(
        [str(SCRIPT), "--json", "--cpu", "0", "--log-file", str(log)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode in {1, 2}
    report = json.loads(result.stdout)
    assert report["exit_code"] == result.returncode
    assert 0 <= report["cpu_percent"] <= 100
    assert 0 <= report["memory_percent"] <= 100
    assert len(report["load_average"]) == 3
    assert len(report["top_processes"]) == 5
    assert report["filesystems"]
    assert report["warnings"]
    assert json.loads(log.read_text()) == report
    assert "CPU" in result.stderr


def test_log_rotation_preserves_previous_entry(tmp_path):
    log = tmp_path / "health_log.txt"
    log.write_text("previous entry\n")
    result = subprocess.run(
        [str(SCRIPT), "--json", "--log-file", str(log), "--max-log-bytes", "1", "--keep-logs", "2"],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode in {0, 1, 2}
    json.loads(result.stdout)
    assert (tmp_path / "health_log.txt.1").read_text() == "previous entry\n"


def test_invalid_threshold_is_configuration_failure():
    result = subprocess.run(
        [str(SCRIPT), "--cpu", "101"],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 2
    assert "Thresholds must be integers" in result.stderr
