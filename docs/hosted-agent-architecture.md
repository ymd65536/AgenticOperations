# Hosted Agent Architecture

This repository adds a second recovery path for the VM+NGINX scenario:

- Rule-based recovery continues to exist via scripts and Logic App automation.
- Hosted Agent recovery is added as a separate, explicit incident workflow.

## Components

- Service Recovery Agent: a code-based agent that uses a constrained tool set.
- Tool Registry: central gatekeeper for all allowed tools.
- Tool implementations: read-only status/log/config tools and controlled write tools.
- System prompt: stored in prompts/service-recovery-agent.system.md.
- Incident payload: structured JSON input describing the issue without revealing root cause.
- Result contract: structured JSON output with status, evidence, actions, and verification.

## Safety boundaries

The agent is not allowed to execute arbitrary shell or SSH. All agent actions are mediated by `ToolRegistry`, which enforces:

- allowed tool names only
- allow-list for NGINX config fields
- prohibited shell-like content
- maximum investigation steps
- maximum configuration changes
- maximum reload attempts
- maximum verification attempts

## Trace and evidence

Each tool call is recorded in the agent result object and can be stored in a JSON Lines audit log. OTel spans can be emitted for:

- Agent invocation
- Model invocation
- Tool invocation
- Remediation
- Verification

The incident ID is used as the correlation key across spans and logs.

## Deployment note

The repository stores a deployment-ready pattern for Microsoft Foundry Agent Service, but the actual Azure deployment requires a Foundry project, model deployment, and the agent code to be published or deployed using the Foundry Hosted Agent flow. This repository provides the orchestration, tool contract, and structured input/output examples, while staying within the repository's deterministic demo boundaries.
