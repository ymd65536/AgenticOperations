from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


@dataclass
class IncidentInput:
    incidentId: str
    scenario: str
    target: Dict[str, Any]
    expectedStatus: int
    observedStatus: int
    agentName: str = "service-recovery-agent"
    modelDeployment: Optional[str] = None


@dataclass
class IncidentResult:
    incidentId: str
    status: str
    observedStatus: int
    finalStatus: int
    rootCause: Dict[str, Any]
    evidence: List[str] = field(default_factory=list)
    actions: List[str] = field(default_factory=list)
    verification: Dict[str, Any] = field(default_factory=dict)
    toolTrace: List[Dict[str, Any]] = field(default_factory=list)
    investigationStepCount: int = 0
    configurationChangeCount: int = 0
    reloadCount: int = 0
    verificationAttemptCount: int = 0
    modelCallCount: Optional[int] = None
    toolCallCount: Optional[int] = None
    inputTokens: Optional[int] = None
    outputTokens: Optional[int] = None
    startTime: Optional[str] = None
    endTime: Optional[str] = None
    totalDurationMs: Optional[int] = None
    toolNames: List[str] = field(default_factory=list)
    finalDisposition: str = "pending"
    agentName: str = "service-recovery-agent"
    modelDeployment: Optional[str] = None
    scenario: str = "vm-nginx-404"
