import json
import subprocess
import sys
from pathlib import Path

import pytest

from hosted_agent.service_recovery_agent import ServiceRecoveryAgent
from hosted_agent.tool_registry import ToolRegistry
from hosted_agent.tool_contracts import IncidentInput, IncidentResult


@pytest.fixture
def incident_input():
    return IncidentInput(
        incidentId="inc-nginx-404-001",
        scenario="vm-nginx-404",
        target={"type": "azure-vm", "url": "http://127.0.0.1/health"},
        expectedStatus=200,
        observedStatus=404,
    )


def test_http_404_does_not_force_root_cause(incident_input):
    agent = ServiceRecoveryAgent(ToolRegistry())
    result = agent.run(incident_input, simulate_healthy_after_recovery=True)
    summary = result.rootCause["summary"].lower()
    assert "location" in summary
    assert "service outage" not in summary


def test_deployed_agent_entrypoint_imports_from_same_directory():
    source_dir = Path(__file__).resolve().parents[2] / "foundry-agent-demo" / "src" / "hosted-agent"
    result = subprocess.run(
        [sys.executable, "-c", "from service_recovery_agent import ServiceRecoveryAgent; print(ServiceRecoveryAgent.__name__)", "--"],
        cwd=str(source_dir),
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def test_read_tools_before_write_tools(incident_input):
    agent = ServiceRecoveryAgent(ToolRegistry())
    result = agent.run(incident_input, simulate_healthy_after_recovery=True)
    assert result.toolTrace[0]["toolName"] == "probe_http"
    assert "update_nginx_health_route" not in result.toolTrace[0:3]


def test_validation_failure_prevents_reload(incident_input):
    agent = ServiceRecoveryAgent(ToolRegistry())
    result = agent.run(
        incident_input,
        simulate_validation_failure=True,
        simulate_healthy_after_recovery=False,
    )
    assert result.status in {"Escalated", "Failed"}
    assert all(event["toolName"] != "reload_nginx" for event in result.toolTrace)


def test_configuration_change_limit(incident_input):
    agent = ServiceRecoveryAgent(ToolRegistry())
    result = agent.run(
        incident_input,
        simulate_multiple_change_attempts=True,
        simulate_healthy_after_recovery=True,
    )
    assert result.configurationChangeCount <= 1


def test_reload_limit(incident_input):
    agent = ServiceRecoveryAgent(ToolRegistry())
    result = agent.run(
        incident_input,
        simulate_reload_failure=True,
        simulate_healthy_after_recovery=False,
    )
    assert result.reloadCount <= 1


def test_resolution_requires_http_200(incident_input):
    agent = ServiceRecoveryAgent(ToolRegistry())
    result = agent.run(
        incident_input,
        simulate_healthy_after_recovery=False,
    )
    assert result.status in {"Escalated", "Failed"}
    assert result.finalStatus != 200


def test_http_404_continuation_escalates(incident_input):
    agent = ServiceRecoveryAgent(ToolRegistry())
    result = agent.run(
        incident_input,
        simulate_healthy_after_recovery=False,
        simulate_http_stays_404=True,
    )
    assert result.status in {"Escalated", "Failed"}
    assert result.finalStatus == 404


def test_unknown_tool_rejected(incident_input):
    registry = ToolRegistry()
    with pytest.raises(ValueError):
        registry.invoke("execute_shell", {})


def test_shell_execution_is_blocked(incident_input):
    registry = ToolRegistry()
    with pytest.raises(ValueError):
        registry.invoke("execute_shell", {"command": "cat /etc/passwd"})


def test_tool_input_allow_list_works():
    registry = ToolRegistry()
    with pytest.raises(ValueError):
        registry.invoke(
            "update_nginx_health_route",
            {"location": "/admin", "root": "/var/www/html"},
        )


def test_cancellation_token_propagates(incident_input):
    agent = ServiceRecoveryAgent(ToolRegistry())
    cancelled = False

    class CancelToken:
        def is_cancelled(self):
            return True

    try:
        agent.run(incident_input, cancellation_token=CancelToken())
    except RuntimeError as exc:
        assert "cancelled" in str(exc).lower()
        cancelled = True

    assert cancelled
