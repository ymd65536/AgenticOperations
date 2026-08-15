# Scenario: azure-functions-route-404

## Purpose

This scenario demonstrates a deterministic HTTP 404 caused by a route mismatch in the Azure Functions configuration rather than by application code returning NotFound intentionally.

## Scenario metadata

- Scenario ID: functions-route-404
- Azure service: Azure Functions (isolated .NET worker)
- Monitored URL: https://<function-app-name>.azurewebsites.net/api/products
- Healthy behavior: HTTP 200 with body `azure-agentic-ops functions healthy`
- Injected failure: `Route = "inventory"` replaces the healthy `Route = "products"`
- Expected HTTP status while broken: 404
- Root cause: the deployed route no longer matches the monitored endpoint
- Recovery procedure: restore the expected route and redeploy the app
- Verification procedure: call the same monitored URL and compare the HTTP status

## Healthy state

The healthy function is configured with:

```csharp
[HttpTrigger(AuthorizationLevel.Function, "get", Route = "products")]
```

This returns HTTP 200 and a short identifying body.

## Broken state

The broken version changes the trigger route to:

```csharp
[HttpTrigger(AuthorizationLevel.Function, "get", Route = "inventory")]
```

The monitored URL still points to `/api/products`, so Azure Functions cannot resolve the request and returns HTTP 404.

## Why the 404 happens

Azure Functions resolves handler routes at startup time. When the path name changes, the runtime has no matching route for the monitored URL. This is a configuration and routing failure, not a server outage or an explicit app-level 404 response.

## Fault injection procedure

```bash
./scripts/deploy.sh functions-route-404
./scripts/break.sh functions-route-404
```

The break script publishes the broken function app package and deploys it to the same Azure Function App.

## Recovery procedure

```bash
./scripts/recover.sh functions-route-404
```

This repackages the healthy function app and redeploys it to restore `/api/products`.

## Verification procedure

```bash
./scripts/verify.sh functions-route-404 healthy
./scripts/verify.sh functions-route-404 broken
```

The verification script prints the scenario ID, URL, expected status, actual status, and PASS/FAIL. It exits with non-zero status when the result differs from expectation.

## Rule Engine decision material

- The monitored URL is stable and deterministic.
- Healthy state returns 200; broken state returns 404.
- Azure Function App remains available; only route resolution changes.
- `Route = "products"` is present in healthy build and absent in broken build.
- The function app deployment payload differs only in runtime route configuration.

## AI Agent investigation evidence

- Azure Function App deployment logs
- Application logs showing the route configuration being active
- Function App configuration showing HTTP trigger route metadata
- The monitored URL and result status under healthy and broken states
- Deployment packages generated from the healthy and broken versions of the app
