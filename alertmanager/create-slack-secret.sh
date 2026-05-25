#!/bin/bash
# Run this ONCE after cluster is up — before helm install
# This stores the Slack webhook as a Kubernetes Secret (never goes into Git)

kubectl create secret generic slack-webhook \
  --from-literal=webhook-url='YOUR_WEBHOOK_HERE' \
  -n monitoring

echo "Slack webhook secret created in monitoring namespace."
