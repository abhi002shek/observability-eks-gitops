#!/bin/bash
set -e

CLUSTER_NAME="obs-practice"
REGION="ap-south-1"
NAMESPACE="monitoring"
ARGOCD_NS="argocd"

echo "======================================"
echo " STEP 1: Create EKS Cluster"
echo "======================================"
eksctl create cluster -f cluster-new.yaml
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

echo "======================================"
echo " STEP 2: Install Prometheus + Grafana + AlertManager"
echo "======================================"
kubectl create namespace $NAMESPACE

# Create Slack webhook secret BEFORE helm install (never stored in Git)
bash alertmanager/create-slack-secret.sh

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace $NAMESPACE \
  --set grafana.adminPassword=admin123 \
  --set grafana.service.type=LoadBalancer \
  --set prometheus.service.type=LoadBalancer \
  --set prometheus.prometheusSpec.additionalScrapeConfigs[0].job_name=otel-gateway \
  --set prometheus.prometheusSpec.additionalScrapeConfigs[0].static_configs[0].targets[0]=otel-gateway.observability.svc.cluster.local:8889 \
  -f alertmanager/alertmanager-values.yaml \
  --wait

echo "======================================"
echo " STEP 3: Install Loki (lightweight)"
echo "======================================"
helm install loki grafana/loki -n $NAMESPACE \
  -f loki-values.yaml \
  --wait

echo "======================================"
echo " STEP 4: Install Tempo (tracing)"
echo "======================================"
helm install tempo grafana/tempo -n $NAMESPACE \
  -f Tempo/tempo-minimal.yaml \
  --wait

echo "======================================"
echo " STEP 5: Deploy OTEL Collector"
echo "======================================"
kubectl create namespace observability
kubectl apply -f OTEL/otel-agent-config.yaml
kubectl apply -f OTEL/otel-agent-daemonset.yaml
kubectl apply -f OTEL/otel-gateway-config.yaml
kubectl apply -f OTEL/otel-gateway-deployment.yaml
kubectl apply -f OTEL/otel-gateway-service.yaml

kubectl rollout status daemonset/otel-agent -n observability
kubectl rollout status deployment/otel-gateway -n observability

echo "======================================"
echo " STEP 6: Install ArgoCD"
echo "======================================"
kubectl create namespace $ARGOCD_NS
kubectl apply -n $ARGOCD_NS -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available deployment/argocd-server -n $ARGOCD_NS --timeout=180s

# Expose ArgoCD UI via LoadBalancer
kubectl patch svc argocd-server -n $ARGOCD_NS \
  -p '{"spec": {"type": "LoadBalancer"}}'

echo "======================================"
echo " STEP 7: Apply SLO Rules + Alert Rules"
echo "======================================"
kubectl apply -f springboot-slo-rules.yaml
kubectl apply -f alertmanager/springboot-alert-rules.yaml

echo "======================================"
echo " STEP 8: Deploy Spring Boot via ArgoCD (GitOps)"
echo "======================================"
# ArgoCD Application — points to GitHub repo, auto-syncs
kubectl apply -f argocd/springboot-application.yaml

echo "Waiting for ArgoCD to sync Spring Boot app..."
sleep 30
kubectl wait --for=condition=available deployment/springboot-app -n app --timeout=180s || true

# ServiceMonitor is in apps/springboot/ in Git — ArgoCD deploys it
# But it needs to be in monitoring namespace — apply directly
kubectl apply -f apps/springboot/servicemonitor.yaml

echo "======================================"
echo " STEP 9: Install Promtail (log collection)"
echo "======================================"
helm install promtail grafana/promtail -n $NAMESPACE \
  --set daemonset.enabled=true \
  --set deployment.enabled=false \
  --set "config.clients[0].url=http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push" \
  --set tolerations[0].operator=Exists \
  --set resources.requests.cpu=10m \
  --set resources.requests.memory=32Mi \
  --set resources.limits.cpu=50m \
  --set resources.limits.memory=64Mi \
  --set config.positions.filename=/tmp/positions.yaml \
  --set volumes[0].name=varlog \
  --set volumes[0].hostPath.path=/var/log \
  --set volumeMounts[0].name=varlog \
  --set volumeMounts[0].mountPath=/var/log \
  --set volumes[1].name=containers \
  --set volumes[1].hostPath.path=/var/log/containers \
  --set volumeMounts[1].name=containers \
  --set volumeMounts[1].mountPath=/var/log/containers \
  --wait

echo "======================================"
echo " STEP 10: Get Access URLs"
echo "======================================"
echo "Waiting for LoadBalancer IPs..."
sleep 90

GRAFANA_URL=$(kubectl get svc kube-prometheus-stack-grafana -n $NAMESPACE \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
PROM_URL=$(kubectl get svc kube-prometheus-stack-prometheus -n $NAMESPACE \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
APP_URL=$(kubectl get svc springboot-service -n app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
ARGOCD_URL=$(kubectl get svc argocd-server -n $ARGOCD_NS \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
ARGOCD_PASS=$(kubectl get secret argocd-initial-admin-secret -n $ARGOCD_NS \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    STACK IS LIVE                            ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Grafana    : http://$GRAFANA_URL"
echo "║  Login      : admin / admin123"
echo "║  Prometheus : http://$PROM_URL:9090"
echo "║  App        : http://$APP_URL"
echo "║  ArgoCD     : https://$ARGOCD_URL"
echo "║  ArgoCD     : admin / $ARGOCD_PASS"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "In Grafana, add these data sources manually:"
echo "  Loki  → http://loki-gateway.monitoring.svc.cluster.local"
echo "  Tempo → http://tempo.monitoring.svc.cluster.local:3100"
echo ""
echo "Import dashboards from JSON files:"
echo "  Springboot_User_Experience-1775208144643.json"
echo "  Springboot_JVM_&_Application_Health-1775208091650.json"
echo "  Springboot_Resource_&_Stability-1775208127698.json"
echo ""
echo "Practice incidents:"
echo "  source incident-scripts/simulate.sh"
echo "  Then call: scenario_drift, scenario_error_spike, scenario_oom, etc."
echo ""
echo "Destroy when done:"
echo "  eksctl delete cluster --name obs-practice --region ap-south-1"
