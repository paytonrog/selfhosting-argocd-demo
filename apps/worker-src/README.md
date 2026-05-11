# Temporal Worker (Node.js + TypeScript)

This folder contains a real Temporal worker scaffold.

## Build and push image

Use your own image registry/repo. Example:

1. `docker build -t ghcr.io/paytonrog/temporal-worker-ts:latest apps/worker-src`
2. `docker push ghcr.io/paytonrog/temporal-worker-ts:latest`

## Deploy with Argo

After pushing an image, update `apps/temporal-workers/deployment.yaml` image value and commit/push.
Argo CD will sync it to the cluster.