#!/bin/bash
# ============================================================
#  INCIDENT SIMULATION SCRIPTS
#  Run these after setup to practice real SRE debugging
#  Each script simulates a real production incident
# ============================================================

APP_PORT=8090

port_forward() {
  kubectl port-forward svc/springboot-service -n app $APP_PORT:80 &>/dev/null &
  PF_PID=$!
  sleep 2
  echo "Port-forward PID: $PF_PID (kill with: kill $PF_PID)"
}

# ============================================================
#  SCENARIO 1: Generate normal traffic (baseline)
# ============================================================
scenario_traffic() {
  echo ">>> Generating normal traffic (50 requests)..."
  for i in {1..50}; do
    curl -s http://localhost:$APP_PORT/ > /dev/null
    sleep 0.2
  done
  echo "Done. Check Grafana → User Experience dashboard"
}

# ============================================================
#  SCENARIO 2: Simulate high error rate (kill pods mid-traffic)
# ============================================================
scenario_error_spike() {
  echo ">>> Simulating error spike — deleting pods while traffic flows..."
  for i in {1..30}; do curl -s http://localhost:$APP_PORT/ > /dev/null & done
  kubectl delete pods -n app -l app=springboot --force --grace-period=0
  echo "Pods deleted. Watch Grafana Error Rate panel spike."
  echo "ArgoCD will detect drift and re-deploy from Git automatically."
  echo "Check: kubectl get pods -n app -w"
}

# ============================================================
#  SCENARIO 3: Simulate OOM / memory pressure
# ============================================================
scenario_oom() {
  echo ">>> Patching deployment to reduce memory limit to 64Mi (will OOM)..."
  kubectl patch deployment springboot-app -n app \
    --type='json' \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"64Mi"}]'
  echo "Watch: kubectl get pods -n app -w"
  echo "Expect: OOMKilled → restart loop → PodRestartLoop alert fires"
  echo ""
  echo "To recover (GitOps way): git push the correct deployment.yaml"
  echo "ArgoCD selfHeal will restore it. Or run: scenario_oom_recover"
}

scenario_oom_recover() {
  echo ">>> Restoring memory limit via kubectl (simulates hotfix before GitOps sync)..."
  kubectl patch deployment springboot-app -n app \
    --type='json' \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"512Mi"}]'
  echo "Note: ArgoCD will detect this as drift from Git and may revert it."
  echo "Proper fix: update deployment.yaml in Git and push."
}

# ============================================================
#  SCENARIO 4: Scale down to 0 (simulate outage)
# ============================================================
scenario_outage() {
  echo ">>> Scaling down to 0 replicas — full outage simulation..."
  kubectl scale deployment springboot-app -n app --replicas=0
  echo "App is down. SpringBootPodDown alert should fire in ~1 min."
  echo "Check AlertManager: kubectl port-forward svc/alertmanager-operated -n monitoring 9093:9093"
  echo "Recover: kubectl scale deployment springboot-app -n app --replicas=2"
  echo "OR: ArgoCD selfHeal will restore to 2 replicas from Git within ~3 min"
}

# ============================================================
#  SCENARIO 5: Simulate high latency (add sleep endpoint)
# ============================================================
scenario_latency() {
  echo ">>> Sending 20 requests to /slow endpoint (if exists) or flooding normal endpoint..."
  for i in {1..20}; do
    curl -s --max-time 5 http://localhost:$APP_PORT/slow > /dev/null &
  done
  wait
  echo "Check Grafana → P95 Latency panel. Trace in Tempo → TraceQL: {resource.service.name=\"springboot-app\"}"
}

# ============================================================
#  SCENARIO 6: Drift detection demo (ArgoCD core feature)
# ============================================================
scenario_drift() {
  echo ">>> Manually changing replica count (simulating someone doing kubectl apply directly)..."
  kubectl scale deployment springboot-app -n app --replicas=5
  echo "Replicas set to 5 manually."
  echo "Now watch ArgoCD UI — it will show 'OutOfSync' status."
  echo "ArgoCD selfHeal will revert to 2 replicas (from Git) within ~3 min."
  echo "This is DRIFT DETECTION — core GitOps concept."
  echo ""
  echo "ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "Login: admin / (get password with: argocd_password)"
}

argocd_password() {
  kubectl get secret argocd-initial-admin-secret -n argocd \
    -o jsonpath="{.data.password}" | base64 -d && echo
}

# ============================================================
#  SCENARIO 7: Full observability trace — the interview story
# ============================================================
scenario_full_trace() {
  echo ">>> Full observability scenario: traffic → error → trace → log"
  echo ""
  echo "Step 1: Generate traffic"
  for i in {1..10}; do curl -s http://localhost:$APP_PORT/ > /dev/null; done
  echo "  ✅ Traffic sent"
  echo ""
  echo "Step 2: Check metrics in Grafana"
  echo "  → Open Grafana → Springboot User Experience dashboard"
  echo "  → Look at: Request Rate, Error Rate, P95 Latency"
  echo ""
  echo "Step 3: Find a trace in Tempo"
  echo "  → Grafana → Explore → Tempo datasource"
  echo "  → Query: {resource.service.name=\"springboot-app\"}"
  echo "  → Click a trace → see spans"
  echo ""
  echo "Step 4: Correlate with logs in Loki"
  echo "  → Grafana → Explore → Loki datasource"
  echo "  → Query: {namespace=\"app\"}"
  echo "  → Filter by traceID from Tempo"
  echo ""
  echo "This is the full observability loop: Metrics → Traces → Logs"
}

# ============================================================
#  MAIN MENU
# ============================================================
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         INCIDENT SIMULATION TOOLKIT                 ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  1. scenario_traffic      — Normal traffic baseline  ║"
echo "║  2. scenario_error_spike  — Error rate spike         ║"
echo "║  3. scenario_oom          — OOM / memory pressure    ║"
echo "║  4. scenario_outage       — Full outage (0 replicas) ║"
echo "║  5. scenario_latency      — High latency simulation  ║"
echo "║  6. scenario_drift        — ArgoCD drift detection   ║"
echo "║  7. scenario_full_trace   — Full M+T+L walkthrough   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Usage: source incident-scripts/simulate.sh"
echo "Then call any function above, e.g.: scenario_drift"
echo ""
echo "First run port_forward to expose the app locally."
