# Scenario: static-web-app-route-404

## Purpose

This scenario reproduces a deterministic HTTP 404 caused by a broken Static Web Apps route configuration rather than by a missing page or a service outage.

## Healthy state

The healthy app includes a valid `navigationFallback` rewrite that sends requests to `/index.html`.

## Broken state

The broken app points `navigationFallback` to a non-existent page (`/missing.html`). Requests that are not otherwise matched will therefore return 404 even though the app itself is still deployed successfully.

## Root cause

The routing configuration is incorrect. The destination of `navigationFallback` no longer resolves to a valid asset.

## Recovery procedure

Restore the healthy `staticwebapp.config.json` and redeploy the app.

## Verification procedure

Use a known monitored path such as `/` or `/index.html` and compare the HTTP response code to the expected value.

## Rule Engine evidence

- HTTP status differs between healthy and broken configuration
- `navigationFallback` target is valid vs broken
- Deployed assets remain present

## AI Agent evidence

- Deployed `staticwebapp.config.json`
- Asset list in the app package
- HTTP status for the monitored path under healthy and broken configuration
