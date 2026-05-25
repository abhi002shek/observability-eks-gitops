#!/bin/bash
# Run this ONCE after cluster is up — before helm install
# Replace WEBHOOK_URL below with your actual Slack webhook (never commit the real value)
# Get it from: https://api.slack.com/apps → your app → Incoming Webhooks

WEBHOOK_URL="${SLACK_WEBHOOK_URL:-YOUR_WEBHOOK_HERE}"

if [ "$WEBHOOK_URL" = "YOUR_WEBHOOK_HERE" ]; then
  echo "ERROR: Set SLACK_WEBHOOK_URL env var before running this script"
  echo "  export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...'"
  exit 1
fi

kubectl create secret generic slack-webhook \
  --from-literal=webhook-url="$WEBHOOK_URL" \
  -n monitoring

echo "Slack webhook secret created in monitoring namespace."
