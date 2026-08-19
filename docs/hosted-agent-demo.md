# Hosted Agent Demo

This demo validates a single-agent recovery flow for the VM + NGINX 404 scenario.

## Input contract

The agent receives only an incident payload such as:

```json
{
  "incidentId": "inc-nginx-404-001",
  "scenario": "vm-nginx-404",
  "target": {
    "type": "azure-vm",
    "url": "http://<vm-ip>/health"
  },
  "expectedStatus": 200,
  "observedStatus": 404,
  "agentName": "service-recovery-agent"
}
```

No root cause or configuration path is provided.

## Safe policy

The agent must complete the following loop:

1. probe HTTP
2. inspect service and logs
3. inspect active NGINX config
4. estimate likely cause from evidence
5. use update_nginx_health_route
6. validate nginx config
7. reload nginx
8. re-probe URL
9. resolve only if HTTP 200 returns

If the evidence is insufficient or config validation fails, the agent must escalate.

## Demo command

```bash
./scripts/run-agent-demo.sh vm-nginx-404
```

The script does the following:

- verifies healthy state
- injects the deterministic 404
- confirms the broken state
- invokes the local hosted agent simulation
- saves the structured result under results/hosted-agent
- verifies the site is healthy again

## Result format

The result is stored as JSON and includes:

- incident ID
- scenario
- status
- final HTTP status
- root cause summary
- evidence list
- actions
- verification payload
- tool trace
