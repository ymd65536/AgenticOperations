# Copilot Instructions

## Repository purpose

This repository intentionally contains breakable Azure workloads for evaluating autonomous incident operations.

## Scope

Do not add AI remediation, Foundry integration, rule engines, or observability orchestration unless explicitly requested.

## Scenario constraints

- Keep each workload deterministic and reproducible.
- Prefer a single, clear failure mechanism.
- Preserve healthy and broken configuration versions in source control.
- Keep recoverability explicit and idempotent.
- Use Azure resources appropriate for development and validation only.

## Required patterns

- Use Bicep under infra/.
- Keep app code and infra separate.
- Store scenario documentation under scenarios/<scenario-id>/README.md.
- Provide scripts for deploy, break, recover, verify, and destroy.
