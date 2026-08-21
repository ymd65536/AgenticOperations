from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List


class ToolRegistry:
    """Allow-listed tool registry for the service recovery agent."""

    ALLOWED_READ_TOOLS = {
        "probe_http",
        "get_nginx_service_status",
        "get_nginx_access_log",
        "get_nginx_error_log",
        "get_nginx_active_config",
    }

    ALLOWED_WRITE_TOOLS = {
        "update_nginx_health_route",
        "validate_nginx_config",
        "reload_nginx",
    }

    BLOCKED_TOOLS = {
        "execute_shell",
        "run_command",
        "execute_azure_cli",
        "ssh_command",
        "arbitrary_file_write",
    }

    def __init__(self):
        self._tool_history: List[str] = []

    def list_allowed_tools(self) -> Dict[str, List[str]]:
        return {
            "read_only": sorted(self.ALLOWED_READ_TOOLS),
            "write": sorted(self.ALLOWED_WRITE_TOOLS),
        }

    def invoke(self, tool_name: str, payload: Dict[str, Any] | None = None) -> Dict[str, Any]:
        if tool_name in self.BLOCKED_TOOLS:
            raise ValueError(f"Tool '{tool_name}' is explicitly blocked.")

        if tool_name not in self.ALLOWED_READ_TOOLS and tool_name not in self.ALLOWED_WRITE_TOOLS:
            raise ValueError(f"Unknown tool '{tool_name}'.")

        self._tool_history.append(tool_name)

        if tool_name == "probe_http":
            return self._probe_http(payload or {})
        if tool_name == "get_nginx_service_status":
            return {"service": "nginx", "status": "active", "details": "systemctl status nginx --no-pager"}
        if tool_name == "get_nginx_access_log":
            return {
                "path": "/var/log/nginx/access.log",
                "lines": ["127.0.0.1 - - [10/Jul/2026:11:00:00 +0000] \"GET /health HTTP/1.1\" 404 123 \"-\" \"curl/8.0\""],
            }
        if tool_name == "get_nginx_error_log":
            return {"path": "/var/log/nginx/error.log", "lines": ["notice: nginx started"]}
        if tool_name == "get_nginx_active_config":
            return {
                "path": "/etc/nginx/conf.d/agentic-ops.conf",
                "location": "/health",
                "root": "/var/www/does-not-exist",
                "content": "location = /health { root /var/www/does-not-exist; }",
            }
        if tool_name == "update_nginx_health_route":
            return self._update_nginx_health_route(payload or {})
        if tool_name == "validate_nginx_config":
            return self._validate_nginx_config(payload or {})
        if tool_name == "reload_nginx":
            return self._reload_nginx(payload or {})

        raise ValueError(f"Tool '{tool_name}' is not implemented.")

    def _resolve_live_url(self, url: str, scenario_id: str = "vm-nginx-404") -> str:
        if not isinstance(url, str) or not url.startswith(("http://", "https://")):
            return url

        state_path = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", ".state", f"{scenario_id}.env")
        )
        public_ip = None
        if os.path.exists(state_path):
            with open(state_path, "r", encoding="utf-8") as env_file:
                for line in env_file:
                    if line.startswith("VM_PUBLIC_IP="):
                        public_ip = line.split("=", 1)[1].strip()
                        break

        if not public_ip:
            return url

        parsed = urllib.parse.urlsplit(url)
        if parsed.hostname and parsed.hostname != public_ip:
            replacement_url = parsed._replace(netloc=public_ip, path=parsed.path or "/health")
            return urllib.parse.urlunsplit(replacement_url)
        return url

    def _probe_http_via_relay(self, url: str, relay_url: str) -> Dict[str, Any]:
        payload = json.dumps({"url": url}).encode("utf-8")
        request = urllib.request.Request(
            relay_url,
            data=payload,
            method="POST",
            headers={"Content-Type": "application/json", "User-Agent": "agentic-ops-hosted-agent/1.0"},
        )

        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                data = json.loads(response.read().decode("utf-8", errors="replace"))
                return {
                    "url": data.get("url", url),
                    "status": int(data.get("status", 503)),
                    "body": data.get("body", ""),
                    "relay": relay_url,
                }
        except urllib.error.HTTPError as exc:
            body = exc.read(4096).decode("utf-8", errors="replace")
            try:
                data = json.loads(body)
                return {"url": data.get("url", url), "status": int(data.get("status", exc.code)), "body": data.get("body", body), "relay": relay_url}
            except Exception:
                return {"url": url, "status": int(exc.code), "body": body, "relay": relay_url}
        except Exception as exc:  # pragma: no cover - network and endpoint specific behavior
            return {"url": url, "status": 503, "body": f"probe_error: {exc}", "error": str(exc), "relay": relay_url}

    def _probe_http(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        scenario_id = payload.get("scenario_id") or payload.get("scenario") or "vm-nginx-404"
        url = self._resolve_live_url(payload.get("url", "http://127.0.0.1/health"), scenario_id=scenario_id)
        if not isinstance(url, str) or not url.startswith(("http://", "https://")):
            raise ValueError("Probe URL must be a valid http or https URL.")

        relay_url = os.environ.get("HTTP_PROBE_ENDPOINT")
        if relay_url:
            return self._probe_http_via_relay(url, relay_url)

        request = urllib.request.Request(
            url,
            method="GET",
            headers={"User-Agent": "agentic-ops-hosted-agent/1.0"},
        )

        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                status = int(response.getcode())
                body = response.read(4096).decode("utf-8", errors="replace")
                return {"url": url, "status": status, "body": body}
        except urllib.error.HTTPError as exc:
            body = exc.read(4096).decode("utf-8", errors="replace")
            return {"url": url, "status": int(exc.code), "body": body}
        except Exception as exc:  # pragma: no cover - network and endpoint specific behavior
            return {"url": url, "status": 503, "body": f"probe_error: {exc}", "error": str(exc)}

    def _update_nginx_health_route(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        if not isinstance(payload, dict):
            raise ValueError("Tool input must be a JSON object.")

        location = payload.get("location")
        root = payload.get("root")

        if location != "/health":
            raise ValueError("Only /health may be updated.")
        if root not in {"/var/www/health", "/var/www/html"}:
            raise ValueError("Only approved root directories are permitted.")

        forbidden = {"include", "directive", "directives", "set", "return", "rewrite"}
        if any(key.lower() in forbidden for key in payload.keys()):
            raise ValueError("Unsafe directive keys are not allowed.")

        raw = json.dumps(payload, separators=(",", ":"))
        if any(token in raw for token in [";", "|", "&", "`", "$", "\n", "\r"]):
            raise ValueError("Unsafe shell-like content is not allowed.")

        return {
            "status": "updated",
            "location": location,
            "root": root,
            "safe": True,
        }

    def _validate_nginx_config(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        if payload.get("simulate_validation_failure"):
            return {"valid": False, "details": "nginx -t failed: invalid root path"}
        return {"valid": True, "details": "nginx -t ok"}

    def _reload_nginx(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        if payload.get("simulate_reload_failure"):
            return {"status": "failed", "details": "nginx reload failed"}
        return {"status": "reloaded", "details": "nginx -s reload succeeded"}

    @property
    def tool_history(self) -> List[str]:
        return list(self._tool_history)
