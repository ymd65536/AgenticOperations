# Hosted Agent safe remote-action design

## Goal

The Azure Hosted Agent must not be given unrestricted SSH access or arbitrary shell execution. Instead, it should operate through a narrow, explicitly allow-listed remote-action channel that is only capable of:

- read-only inspection of nginx health and logs
- syntax validation with `nginx -t`
- safe reload with `nginx -s reload`
- replacement of the approved healthy config file
- verification through `curl` or `./scripts/verify.sh`

This design keeps the agent useful for deterministic incident response while preventing arbitrary commands.

## Why SSH is not granted directly

The Azure Hosted Agent is a managed service and should not be treated as a fully trusted shell runtime. Directory traversal, file modification outside the approved nginx config path, or arbitrary package installation would create unacceptable operational risk.

## Approved channel pattern

The repository provides a constrained wrapper at `scripts/remote-action-channel.sh`.

Allowed actions:

- `inspect`
- `repair`
- `verify`
- `help`

The wrapper stays inside the allow-list and does not accept arbitrary commands. It only performs:

1. `nginx -t`
2. `nginx -s reload`
3. restore the approved healthy nginx configuration
4. run the repo verification script

## Operational flow

```text
break.sh -> 404 confirmed
Hosted Agent guidance invoked
safe remote-action channel executes allowed repair only
recover.sh / verify.sh validate HTTP 200
```

This means the agent can still produce investigation guidance and root-cause reasoning, but the actual live change on the VM is constrained to the approved actions above.

## Security boundary

The remote-action channel should be treated as the only VM mutation path for the hosted agent. It is intentionally narrow and should remain narrow even if the incident prompt grows more complex.

The design requirement is simple:

- no arbitrary shell execution
- no unscoped file writes
- no package installs
- no remote privilege escalation beyond the VM's approved sudo capability
- all changes must be traceable to the repo's healthy config
