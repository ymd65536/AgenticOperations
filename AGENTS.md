# AGENTS.md

## Project overview

This repository provides intentionally breakable Azure workloads for evaluating autonomous incident operations.

The repository contains three independent HTTP 404 scenarios:

1. Azure Virtual Machine running NGINX
2. Azure Functions HTTP-triggered application
3. Azure Static Web Apps application

The purpose of this repository is only to create, break, restore, and verify monitored workloads.

Do not implement AI agents, Microsoft Foundry integration, remediation agents, rule engines, Dapr Workflow, or Copilot Observability orchestration in this repository unless explicitly requested.

A separate system will later monitor and remediate these workloads.

The initial milestone for deterministic lifecycle and rule-based recovery is complete. The next explicit milestone is a Microsoft Foundry Hosted Agent demonstration that investigates a deterministic HTTP 404, selects a safe remediation via allowed tools, validates the change, and verifies recovery without arbitrary shell operations.

## Primary objective

Each workload must provide a deterministic lifecycle:

```text
Healthy
→ Inject failure
→ HTTP 404
→ Restore
→ HTTP 200
```

The same failure must be reproducible repeatedly.

Every scenario must make it possible to distinguish:

* Expected healthy state
* Injected fault
* Observable HTTP 404
* Root cause
* Deterministic remediation
* Verification result

## Design principles

### Reproducibility

Failures must be intentionally created.

Do not depend on random infrastructure failures, race conditions, external outages, or undocumented Azure behavior.

Every failure must have a corresponding deterministic recovery operation.

### Idempotency

The following operations must be safe to run repeatedly:

* deployment
* fault injection
* recovery
* verification
* cleanup

Running `break` twice must not corrupt the environment.

Running `recover` against an already healthy workload must succeed safely.

### Separation of healthy and broken states

Do not create unrelated application bugs.

Each scenario must have exactly one primary failure mechanism.

Healthy and broken configurations should be version controlled separately where practical.

### Observability

Each workload must expose:

* health endpoint where applicable
* deterministic test URL
* HTTP status code
* identifying response body when healthy

Logs must make the injected configuration change or routing failure diagnosable.

Do not intentionally suppress useful diagnostic logs.

### Security

Use development-only Azure resources.

Do not commit:

* credentials
* access tokens
* private SSH keys
* subscription IDs
* tenant IDs
* connection strings containing secrets

Prefer Managed Identity where applicable.

VM SSH access must use public key authentication.

Avoid broad inbound network rules.

### Infrastructure as Code

Provision Azure resources using Bicep.

Infrastructure definitions must be placed under `infra/`.

Application logic and infrastructure definitions must remain separate.

Do not require manual Azure Portal operations for the normal deployment, break, recover, or verification workflow.

## Scenario 1: Azure VM + NGINX

Create a Linux Azure VM running NGINX.

The healthy endpoint must return HTTP 200.

Recommended endpoint:

```text
/
```

or

```text
/health
```

### Failure mechanism

Create an intentionally incorrect NGINX routing configuration that causes a known request path to return HTTP 404.

Prefer an NGINX configuration error such as:

* incorrect `location` path
* wrong document root
* missing mapping to an otherwise existing file

Do not stop NGINX.

Do not stop the VM.

Do not block port 80.

The scenario specifically evaluates HTTP routing remediation, not service availability remediation.

Store healthy and broken NGINX configurations separately.

Recommended structure:

```text
src/nginx/
  healthy.conf
  broken.conf
```

### Recovery

Recovery must:

1. Restore the healthy NGINX configuration
2. Validate configuration with `nginx -t`
3. Reload NGINX
4. Verify the expected endpoint returns HTTP 200

The recovery operation must not reboot the VM unless explicitly requested.

## Scenario 2: Azure Functions

Create an HTTP-triggered Azure Functions application.

Use .NET isolated worker unless an existing repository standard requires another runtime.

The healthy function must return HTTP 200 from a known route.

Example conceptual route:

```text
/api/products
```

### Failure mechanism

The failure must produce HTTP 404 because the requested route is no longer mapped to the function.

Use a deterministic routing mismatch.

Examples include:

* changing the HTTP trigger `Route`
* changing route-prefix behavior
* deploying a version whose route no longer matches the monitored URL

Do not implement the broken state by explicitly returning `HttpStatusCode.NotFound` from otherwise valid application code unless explicitly requested.

The objective is to simulate a routing/configuration problem rather than an application intentionally returning a business-level 404.

The healthy and broken route definitions must be easy to compare.

### Recovery

Restore the expected HTTP route and redeploy the application.

Verification must call the same monitored URL and confirm HTTP 200.

## Scenario 3: Azure Static Web Apps

Create a minimal Azure Static Web Apps application.

The application does not require a frontend framework.

A minimal HTML site is sufficient.

The healthy state must provide HTTP 200 for the monitored route.

### Failure mechanism

Create a deterministic routing or deployment configuration that makes the monitored route return HTTP 404.

Prefer one of the following:

* missing `navigationFallback`
* incorrect fallback configuration
* monitored static path removed from the deployed assets
* routing configuration mismatch

Use `staticwebapp.config.json` for Static Web Apps configuration.

Store healthy and broken versions separately where practical.

The scenario should demonstrate a configuration-driven 404 rather than a random missing resource.

### Recovery

Restore the expected routing or asset configuration and redeploy.

Verification must confirm the original monitored URL returns HTTP 200.

## Scenario metadata

Each scenario must contain a README or machine-readable metadata document describing:

```text
Scenario ID
Azure service
Monitored URL
Healthy behavior
Injected failure
Expected HTTP status while broken
Root cause
Recovery procedure
Verification procedure
```

Recommended scenario IDs:

```text
vm-nginx-404
functions-route-404
static-web-app-route-404
```

## Scripts

Provide repository-level scripts for:

```text
deploy
break
recover
verify
destroy
```

The scripts may accept a scenario name.

Example:

```bash
./scripts/break.sh vm-nginx-404
./scripts/verify.sh vm-nginx-404
./scripts/recover.sh vm-nginx-404
```

Do not create separate undocumented procedures that require operators to remember portal operations.

## Verification

The verification script must fail with a non-zero exit code if the observed status does not match the expected state.

Healthy verification:

```text
HTTP 200 expected
```

Broken verification:

```text
HTTP 404 expected
```

Include the actual status code and tested URL in command output.

## Logging and diagnostic readiness

Design each workload so that a future investigation agent can retrieve enough evidence to identify the root cause.

At minimum preserve diagnostic signals relevant to:

### NGINX

* access log
* error log
* active configuration
* service state

### Azure Functions

* invocation/application logs
* deployed route information
* application configuration
* deployment/version information where practical

### Static Web Apps

* deployed configuration
* deployment state
* expected route configuration

Do not yet implement Azure Monitor alert rules unless explicitly requested.

## Repository scope constraints

Do not add the following in the initial milestone:

* Microsoft Foundry
* Foundry Hosted Agent
* Azure SRE Agent
* Dapr
* rule-based remediation
* automatic remediation
* Copilot Observability
* custom monitoring dashboard
* GPU workloads
* AKS unless required by a later milestone

The initial milestone is complete when all three workloads can independently demonstrate:

```text
deploy → HTTP 200
break → HTTP 404
recover → HTTP 200
```

## Testing

Provide lightweight smoke tests.

Tests must confirm:

* deployment outputs a valid endpoint
* healthy state returns HTTP 200
* broken state returns HTTP 404
* recovery returns the workload to HTTP 200

Tests must not require AI services.

## Documentation

The README must explain:

* project purpose
* architecture
* prerequisites
* Azure resources created
* estimated cost considerations at a high level
* how to deploy
* how to inject each fault
* how to recover each fault
* how to verify each state
* how to destroy all resources

Document any Azure resource that continues to incur cost while idle.

## Implementation order

Implement in this order:

1. Repository skeleton
2. Shared Bicep infrastructure conventions
3. VM + NGINX healthy state
4. VM + NGINX broken/recovery flow
5. Azure Functions healthy state
6. Azure Functions broken/recovery flow
7. Static Web Apps healthy state
8. Static Web Apps broken/recovery flow
9. Unified scripts
10. Smoke tests
11. Documentation

Do not proceed to AI-based remediation until all three deterministic scenarios are reproducible.

## Definition of done

The milestone is complete when:

* all three Azure workloads deploy successfully
* each has one deterministic 404 failure mechanism
* each failure can be injected repeatedly
* each workload can be deterministically recovered
* healthy state returns HTTP 200
* failure state returns HTTP 404
* repository scripts perform all normal operations
* infrastructure is defined as code
* no credentials are committed
* all resources can be removed cleanly
* README documents the exact workflow
