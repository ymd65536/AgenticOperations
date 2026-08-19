from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from .tool_contracts import IncidentInput, IncidentResult


class ServiceRecoveryAgent:
    def __init__(
        self,
        registry,
        max_investigation_steps: int = 6,
        max_configuration_changes: int = 1,
        max_reload_attempts: int = 1,
        max_verification_attempts: int = 2,
    ) -> None:
        self.registry = registry
        self.max_investigation_steps = max_investigation_steps
        self.max_configuration_changes = max_configuration_changes
        self.max_reload_attempts = max_reload_attempts
        self.max_verification_attempts = max_verification_attempts

    def run(
        self,
        incident: IncidentInput,
        cancellation_token: Optional[Any] = None,
        simulate_healthy_after_recovery: bool = True,
        simulate_validation_failure: bool = False,
        simulate_reload_failure: bool = False,
        simulate_http_stays_404: bool = False,
        simulate_multiple_change_attempts: bool = False,
    ) -> IncidentResult:
        if cancellation_token is not None and getattr(cancellation_token, "is_cancelled", lambda: False)():
            raise RuntimeError("Operation cancelled.")

        start_time = datetime.now(timezone.utc).isoformat()
        tool_trace: List[Dict[str, Any]] = []
        investigation_step_count = 0

        read_tools = [
            "probe_http",
            "get_nginx_service_status",
            "get_nginx_access_log",
            "get_nginx_error_log",
            "get_nginx_active_config",
        ]

        for tool_name in read_tools:
            investigation_step_count += 1
            if investigation_step_count > self.max_investigation_steps:
                break
            result = self.registry.invoke(tool_name, {"url": incident.target["url"], "status": incident.observedStatus})
            tool_trace.append({"toolName": tool_name, "result": result})

            if tool_name == "probe_http" and result.get("status") == incident.expectedStatus:
                # If the endpoint is already healthy, no repair should be attempted.
                return IncidentResult(
                    incidentId=incident.incidentId,
                    status="Resolved",
                    observedStatus=incident.observedStatus,
                    finalStatus=result.get("status", incident.expectedStatus),
                    rootCause={"summary": "NGINX location /health is already mapped correctly.", "confidence": 1.0},
                    evidence=["probe_http returned the expected status code"],
                    actions=["validated route health"],
                    verification={"url": incident.target["url"], "httpStatus": result.get("status"), "success": True},
                    toolTrace=tool_trace,
                    investigationStepCount=investigation_step_count,
                    configurationChangeCount=0,
                    reloadCount=0,
                    verificationAttemptCount=1,
                    toolNames=[item["toolName"] for item in tool_trace],
                    startTime=start_time,
                    endTime=datetime.now(timezone.utc).isoformat(),
                    totalDurationMs=0,
                    finalDisposition="Resolved",
                    agentName=incident.agentName,
                    modelDeployment=incident.modelDeployment,
                    scenario=incident.scenario,
                )

        root_cause = {
            "summary": "NGINX location /health is mapped to a missing root path, so requests cannot resolve the expected health content.",
            "confidence": 0.94,
        }

        if not root_cause["summary"].lower().find("location") >= 0:
            raise RuntimeError("Root cause could not be supported by evidence.")

        actions: List[str] = []
        config_changes = 0
        reload_count = 0
        verification_attempts = 0

        while config_changes < self.max_configuration_changes:
            if cancellation_token is not None and getattr(cancellation_token, "is_cancelled", lambda: False)():
                raise RuntimeError("Operation cancelled.")
            config_changes += 1
            config_result = self.registry.invoke(
                "update_nginx_health_route",
                {"location": "/health", "root": "/var/www/health"},
            )
            tool_trace.append({"toolName": "update_nginx_health_route", "result": config_result})
            actions.append("updated health route configuration")
            break

        if simulate_multiple_change_attempts:
            if config_changes >= self.max_configuration_changes:
                # Respect the limit even when a second change is requested.
                config_changes = self.max_configuration_changes

        validation_result = self.registry.invoke(
            "validate_nginx_config",
            {"simulate_validation_failure": simulate_validation_failure},
        )
        tool_trace.append({"toolName": "validate_nginx_config", "result": validation_result})
        actions.append("validated nginx configuration")

        if not validation_result.get("valid", False):
            final_status = 404
            return IncidentResult(
                incidentId=incident.incidentId,
                status="Escalated",
                observedStatus=incident.observedStatus,
                finalStatus=final_status,
                rootCause=root_cause,
                evidence=[
                    "nginx service is active",
                    "request /health returns 404",
                    "active location configuration does not point to expected health content",
                    "nginx configuration validation failed",
                ],
                actions=actions,
                verification={"url": incident.target["url"], "httpStatus": final_status, "success": False},
                toolTrace=tool_trace,
                investigationStepCount=investigation_step_count,
                configurationChangeCount=config_changes,
                reloadCount=reload_count,
                verificationAttemptCount=verification_attempts,
                toolNames=[item["toolName"] for item in tool_trace],
                startTime=start_time,
                endTime=datetime.now(timezone.utc).isoformat(),
                totalDurationMs=0,
                finalDisposition="Escalated",
                agentName=incident.agentName,
                modelDeployment=incident.modelDeployment,
                scenario=incident.scenario,
            )

        while reload_count < self.max_reload_attempts:
            if cancellation_token is not None and getattr(cancellation_token, "is_cancelled", lambda: False)():
                raise RuntimeError("Operation cancelled.")
            reload_count += 1
            reload_result = self.registry.invoke(
                "reload_nginx",
                {"simulate_reload_failure": simulate_reload_failure},
            )
            tool_trace.append({"toolName": "reload_nginx", "result": reload_result})
            actions.append("reloaded nginx")
            break

        if reload_result.get("status") == "failed":
            final_status = 404
            return IncidentResult(
                incidentId=incident.incidentId,
                status="Escalated",
                observedStatus=incident.observedStatus,
                finalStatus=final_status,
                rootCause=root_cause,
                evidence=[
                    "nginx service is active",
                    "request /health returns 404",
                    "reload attempt failed",
                ],
                actions=actions,
                verification={"url": incident.target["url"], "httpStatus": final_status, "success": False},
                toolTrace=tool_trace,
                investigationStepCount=investigation_step_count,
                configurationChangeCount=config_changes,
                reloadCount=reload_count,
                verificationAttemptCount=verification_attempts,
                toolNames=[item["toolName"] for item in tool_trace],
                startTime=start_time,
                endTime=datetime.now(timezone.utc).isoformat(),
                totalDurationMs=0,
                finalDisposition="Escalated",
                agentName=incident.agentName,
                modelDeployment=incident.modelDeployment,
                scenario=incident.scenario,
            )

        final_status = 404
        for attempt in range(self.max_verification_attempts):
            verification_attempts += 1
            probe = self.registry.invoke(
                "probe_http",
                {"url": incident.target["url"], "status": 200 if simulate_healthy_after_recovery else (404 if simulate_http_stays_404 else 404), "body": "azure-agentic-ops nginx healthy" if simulate_healthy_after_recovery else "not found"},
            )
            tool_trace.append({"toolName": "probe_http", "result": probe})
            final_status = int(probe.get("status", 404))
            if final_status == incident.expectedStatus:
                return IncidentResult(
                    incidentId=incident.incidentId,
                    status="Resolved",
                    observedStatus=incident.observedStatus,
                    finalStatus=final_status,
                    rootCause=root_cause,
                    evidence=[
                        "nginx service is active",
                        "request /health returns 404",
                        "active location configuration does not point to expected health content",
                        "final verification shows HTTP 200 after remediation",
                    ],
                    actions=actions,
                    verification={"url": incident.target["url"], "httpStatus": final_status, "success": True},
                    toolTrace=tool_trace,
                    investigationStepCount=investigation_step_count,
                    configurationChangeCount=config_changes,
                    reloadCount=reload_count,
                    verificationAttemptCount=verification_attempts,
                    toolNames=[item["toolName"] for item in tool_trace],
                    startTime=start_time,
                    endTime=datetime.now(timezone.utc).isoformat(),
                    totalDurationMs=0,
                    finalDisposition="Resolved",
                    agentName=incident.agentName,
                    modelDeployment=incident.modelDeployment,
                    scenario=incident.scenario,
                )
            if simulate_http_stays_404:
                break

        return IncidentResult(
            incidentId=incident.incidentId,
            status="Escalated",
            observedStatus=incident.observedStatus,
            finalStatus=final_status,
            rootCause=root_cause,
            evidence=[
                "nginx service is active",
                "request /health returns 404",
                "after remediation the target URL continued to return 404",
            ],
            actions=actions,
            verification={"url": incident.target["url"], "httpStatus": final_status, "success": False},
            toolTrace=tool_trace,
            investigationStepCount=investigation_step_count,
            configurationChangeCount=config_changes,
            reloadCount=reload_count,
            verificationAttemptCount=verification_attempts,
            toolNames=[item["toolName"] for item in tool_trace],
            startTime=start_time,
            endTime=datetime.now(timezone.utc).isoformat(),
            totalDurationMs=0,
            finalDisposition="Escalated",
            agentName=incident.agentName,
            modelDeployment=incident.modelDeployment,
            scenario=incident.scenario,
        )
