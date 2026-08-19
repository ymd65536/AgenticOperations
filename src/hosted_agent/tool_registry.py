from __future__ import annotations

import json
from typing import Any, Dict, Iterable, List


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

    def _probe_http(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        url = payload.get("url", "http://127.0.0.1/health")
        status = payload.get("status", 404)
        body = payload.get("body", "not found")
        return {"url": url, "status": status, "body": body}

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
