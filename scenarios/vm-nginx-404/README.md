# Scenario: vm-nginx-404

## Purpose

This scenario validates a deterministic HTTP 404 caused by a routing configuration problem rather than a VM or NGINX service outage. The workload simulates a future incident-response workflow where the monitored URL must be healthy, then intentionally broken, then recovered without rebooting the VM or stopping NGINX.

## Scenario metadata

- Scenario ID: vm-nginx-404
- Azure service: Azure Linux Virtual Machine running NGINX
- Monitored URL: http://<VM_PUBLIC_IP>/health
- Healthy behavior: HTTP 200 and body contains `azure-agentic-ops nginx healthy`
- Injected failure: wrong `location` and `root` configuration in `/etc/nginx/conf.d/agentic-ops.conf`
- Expected HTTP status while broken: 404
- Root cause: the configuration points the `/health` lookup to a non-existent root path, so NGINX resolves the request to a missing file and returns 404
- Recovery procedure: restore `healthy.conf`, validate with `nginx -t`, reload NGINX, re-check URL
- Verification procedure: call `./scripts/verify.sh vm-nginx-404 healthy|broken`

## Healthy state

The healthy state is the default NGINX configuration created by the VM deployment script. It serves `index.html` from `/var/www/html` and the `/health` route returns HTTP 200 with a small identifying body.

```text
HTTP 200
Body contains: azure-agentic-ops nginx healthy
```

## Broken state

The broken configuration intentionally changes the `location = /health` root to `/var/www/does-not-exist` and then tries to resolve `$uri`. This is still a valid NGINX config, but it makes the monitored route impossible to resolve. NGINX remains running, the VM remains online, port 80 remains open, and the issue is restricted to routing/content lookup.

## Why the 404 happens

The request is made to `/health`, but the `location` block points to a missing filesystem path. NGINX is not stopped, and path resolution in the config fails before the request can reach a valid file. The result is a clean HTTP 404 from the web server, which is exactly the scenario we want to monitor and recover.

## Fault injection procedure

```bash
./scripts/break.sh vm-nginx-404
```

The script copies the `broken.conf` file to the VM, validates the config with `nginx -t`, then reloads NGINX. It then calls verification for the broken state.

## Recovery procedure

```bash
./scripts/recover.sh vm-nginx-404
```

The script copies the healthy config back to the VM, runs `nginx -t`, reloads NGINX, and confirms the monitored URL returns HTTP 200.

## Verification procedure

```bash
./scripts/verify.sh vm-nginx-404 healthy
./scripts/verify.sh vm-nginx-404 broken
```

The script prints:

- scenario ID
- URL
- expected HTTP status
- actual HTTP status
- PASS / FAIL

It exits non-zero if the observed status does not match the expected state.

## Rule Engine decision material

These are signals a future Rule Engine can evaluate without reading the full app state:

- HTTP status from `/health` is `200` when healthy and `404` when broken
- `nginx -t` succeeds in both states
- `nginx -s reload` succeeds after each change
- NGINX process is still running
- active config file is `/etc/nginx/conf.d/agentic-ops.conf`
- the monitored URL is stable and deterministic
- file content of `healthy.conf` and `broken.conf` differs only in `location` routing and root directory

## AI Agent investigation evidence

These are the evidence sources a future autonomous incident agent should inspect:

- `/var/log/nginx/access.log` showing the `/health` request and status code
- `/var/log/nginx/error.log` showing no process-level crash or port block
- `/etc/nginx/conf.d/agentic-ops.conf` showing the active configuration
- `systemctl status nginx --no-pager` indicating the service remains active
- VM resource ID and public IP from Azure deployment metadata
- monitored URL and expected HTTP response body

These evidence points are intentionally stored in a machine- and human-readable form so they can support a later PoC for autonomous diagnosis.

## Diagnostics readiness

The implementation keeps the following diagnostics available without Azure Monitor integration:

- NGINX access log: available at `/var/log/nginx/access.log`
- NGINX error log: available at `/var/log/nginx/error.log`
- Active configuration: `/etc/nginx/conf.d/agentic-ops.conf`
- NGINX service status: `systemctl status nginx --no-pager`
- VM resource identifier: Azure VM resource ID in deployment outputs
- Monitored URL: http://<VM_PUBLIC_IP>/health
