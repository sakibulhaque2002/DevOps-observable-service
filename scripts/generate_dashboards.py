"""Generate the committed Grafana JSON dashboards from explicit panel definitions."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "monitoring/grafana/dashboards"


def panel(title, expressions, x, y, unit="short", kind="timeseries"):
    datasource = (
        {"type": "loki", "uid": "loki"}
        if kind == "logs"
        else {
            "type": "prometheus",
            "uid": "prometheus",
        }
    )
    result = {
        "title": title,
        "type": kind,
        "datasource": datasource,
        "gridPos": {"h": 9, "w": 12, "x": x, "y": y},
        "targets": [
            {"refId": chr(65 + i), "expr": expr, "legendFormat": legend, "datasource": datasource}
            for i, (expr, legend) in enumerate(expressions)
        ],
        "fieldConfig": {"defaults": {"unit": unit}, "overrides": []},
        "options": {
            "legend": {"displayMode": "table", "placement": "bottom"},
            "showTime": True,
            "showLabels": False,
        },
    }
    if kind == "logs":
        result["options"]["wrapLogMessage"] = True
        result["options"]["sortOrder"] = "Descending"
    return result


dashboards = {
    "application": [
        panel(
            "Request rate by route",
            [
                (
                    'sum by(path) (rate(http_requests_total{job="app",path!="/health"}[1m]))',
                    "{{path}}",
                ),
            ],
            0,
            0,
            "reqps",
        ),
        panel(
            "Server error rate (%)",
            [
                (
                    '100 * (sum(rate(http_errors_total{job="app",status=~"5.."}[1m])) '
                    "or vector(0)) "
                    '/ clamp_min(sum(rate(http_requests_total{job="app"}[1m])), 0.001)',
                    "5xx %",
                ),
            ],
            12,
            0,
            "percent",
        ),
        panel(
            "Request latency: p50 / p95 / p99",
            [
                (
                    f"histogram_quantile({q}, sum by(le) (rate(http_request_duration_seconds_bucket"
                    '{job="app",path!="/health"}[1m])))',
                    label,
                )
                for q, label in [(0.5, "p50"), (0.95, "p95"), (0.99, "p99")]
            ],
            0,
            9,
            "s",
        ),
        panel(
            "Application logs — filter JSON fields in Explore",
            [
                ('{service="app"} | json', ""),
            ],
            12,
            9,
            kind="logs",
        ),
    ],
    "host": [
        panel(
            "Host CPU usage",
            [
                (
                    '100 * (1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[1m])))',
                    "{{instance}}",
                ),
            ],
            0,
            0,
            "percent",
        ),
        panel(
            "Host memory usage",
            [
                (
                    "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)",
                    "{{instance}}",
                ),
            ],
            12,
            0,
            "percent",
        ),
        panel(
            "Disk usage by mounted filesystem",
            [
                (
                    '100 * (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"} '
                    '/ node_filesystem_size_bytes{fstype!~"tmpfs|overlay|squashfs"})',
                    "{{mountpoint}}",
                ),
            ],
            0,
            9,
            "percent",
        ),
        panel(
            "Network receive / transmit",
            [
                (
                    "rate(node_network_receive_bytes_total"
                    '{device!~"lo|veth.*|br-.*|docker.*"}[1m])',
                    "{{device}} receive",
                ),
                (
                    "rate(node_network_transmit_bytes_total"
                    '{device!~"lo|veth.*|br-.*|docker.*"}[1m])',
                    "{{device}} transmit",
                ),
            ],
            12,
            9,
            "Bps",
        ),
    ],
    "containers": [
        panel(
            "Container CPU usage (cores)",
            [
                (
                    "sum by(name) (rate(container_cpu_usage_seconds_total"
                    '{job="cadvisor",name=~"devops-observable.*",image!=""}[1m]))',
                    "{{name}}",
                ),
            ],
            0,
            0,
            "short",
        ),
        panel(
            "Container memory working set",
            [
                (
                    "sum by(name) (container_memory_working_set_bytes"
                    '{job="cadvisor",name=~"devops-observable.*",image!=""})',
                    "{{name}}",
                ),
            ],
            12,
            0,
            "bytes",
        ),
        panel(
            "Container memory relative to limit",
            [
                (
                    "100 * (container_memory_working_set_bytes"
                    '{job="cadvisor",name=~"devops-observable.*",image!=""} '
                    "/ container_spec_memory_limit_bytes"
                    '{job="cadvisor",name=~"devops-observable.*",image!=""}) '
                    "and container_spec_memory_limit_bytes"
                    '{job="cadvisor",name=~"devops-observable.*",image!=""} > 0 '
                    "and container_spec_memory_limit_bytes"
                    '{job="cadvisor",name=~"devops-observable.*",image!=""} < 1e15',
                    "{{name}}",
                ),
            ],
            0,
            9,
            "percent",
        ),
    ],
}

for slug, panels in dashboards.items():
    for number, item in enumerate(panels, 1):
        item["id"] = number
    dashboard = {
        "uid": f"devops-{slug}",
        "title": f"DevOps / {slug.title()}",
        "tags": ["devops-assessment"],
        "schemaVersion": 39,
        "version": 1,
        "refresh": "10s",
        "timezone": "browser",
        "time": {"from": "now-15m", "to": "now"},
        "panels": panels,
    }
    (ROOT / f"{slug}.json").write_text(json.dumps(dashboard, indent=2) + "\n")
    print(f"Generated {slug}.json")
