#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-myapp}"
BACKEND="${K8SGPT_BACKEND:-ollama}"
MODEL="${K8SGPT_MODEL:-llama3.2:3b}"
REPORT_DIR="docs/debug"
REPORT_FILE="${REPORT_DIR}/ai-k8s-diagnosis-${NAMESPACE}-$(date +%Y%m%d-%H%M%S).txt"

mkdir -p "$REPORT_DIR"

echo "Running AI Kubernetes diagnosis..."
echo "Namespace: ${NAMESPACE}"
echo "Backend: ${BACKEND}"
echo "Model: ${MODEL}"

{
  echo "===== AI Kubernetes Diagnosis ====="
  echo "Date: $(date)"
  echo "Namespace: ${NAMESPACE}"
  echo "Backend: ${BACKEND}"
  echo "Model: ${MODEL}"
  echo

  echo "===== Kubernetes Objects ====="
  kubectl get deploy,rs,pods,svc,ingress,job -n "$NAMESPACE" -o wide || true
  echo

  echo "===== Recent Events ====="
  kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -50 || true
  echo

  echo "===== Pod Logs ====="
  for pod in $(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}' | head -5); do
    echo
    echo "----- Pod: ${pod} -----"
    kubectl logs "$pod" -n "$NAMESPACE" --tail=80 --all-containers=true 2>/dev/null || true
  done
  echo

  echo "===== K8sGPT Analysis ====="
  k8sgpt analyze --namespace "$NAMESPACE" --explain --backend "$BACKEND" || true
} | tee "$REPORT_FILE"

SUMMARY="$(awk '
  /===== K8sGPT Analysis =====/ {flag=1; next}
  flag {print}
' "$REPORT_FILE" | head -50)"

if [ -z "$SUMMARY" ]; then
  SUMMARY="No K8sGPT findings were returned. Check pod logs, events, readiness probes, image pull status, and recent GitOps changes."
fi

SLACK_WEBHOOK_URL="$(kubectl get secret alertmanager-slack-webhook \
  -n monitoring \
  -o jsonpath='{.data.webhook-url}' | base64 -d)"

PAYLOAD="$(python3 - <<PY
import json
namespace = "${NAMESPACE}"
backend = "${BACKEND}"
model = "${MODEL}"
summary = """${SUMMARY}"""
report = "${REPORT_FILE}"

text = f"""🤖 *AI Kubernetes Diagnosis*

*Namespace:* `{namespace}`
*Environment:* `local-kind`
*AI Backend:* `{backend}`
*Model:* `{model}`

*Summary / Findings:*
```{summary[:2500]}```

*Recommended Next Action:*
Review the generated local report:
`{report}`

*Useful links:*
• Grafana: http://grafana.127.0.0.1.nip.io
• Prometheus: http://prometheus.127.0.0.1.nip.io/alerts
• Alertmanager: http://alertmanager.127.0.0.1.nip.io
"""

print(json.dumps({"text": text}))
PY
)"

curl -sS -X POST \
  -H 'Content-type: application/json' \
  --data "$PAYLOAD" \
  "$SLACK_WEBHOOK_URL"

unset SLACK_WEBHOOK_URL

echo
echo "Report saved: ${REPORT_FILE}"
echo "AI diagnosis posted to Slack #skm_alerts."
