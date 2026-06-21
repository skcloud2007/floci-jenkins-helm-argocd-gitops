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
  kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -40 || true
  echo

  echo "===== Unhealthy Pods ====="
  kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" {print $1 " " $3}' || true
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

SLACK_WEBHOOK_URL="$(kubectl get secret alertmanager-slack-webhook \
  -n monitoring \
  -o jsonpath='{.data.webhook-url}' | base64 -d)"

export NAMESPACE BACKEND MODEL REPORT_FILE

PAYLOAD="$(python3 - <<'PY'
import json
import os
import re
from pathlib import Path

namespace = os.environ["NAMESPACE"]
backend = os.environ["BACKEND"]
model = os.environ["MODEL"]
report_file = os.environ["REPORT_FILE"]

report = Path(report_file).read_text(errors="ignore")

def extract_section(title, next_title=None):
    start = f"===== {title} ====="
    if start not in report:
        return ""
    part = report.split(start, 1)[1]
    if next_title:
        end = f"===== {next_title} ====="
        if end in part:
            part = part.split(end, 1)[0]
    return part.strip()

objects = extract_section("Kubernetes Objects", "Recent Events")
events = extract_section("Recent Events", "Unhealthy Pods")
unhealthy = extract_section("Unhealthy Pods", "Pod Logs")
analysis = extract_section("K8sGPT Analysis")

if not unhealthy:
    unhealthy = "No unhealthy pods detected."

if not analysis:
    analysis = "No active K8sGPT findings were returned for this namespace."

events_short = "\n".join(events.splitlines()[-8:]) if events else "No recent events found."
analysis_short = analysis[:1800]
events_short = events_short[:1200]
unhealthy_short = unhealthy[:800]

lower = f"{analysis} {events} {unhealthy}".lower()

if "imagepullbackoff" in lower or "errimagepull" in lower:
    next_action = "Check image repository, tag, registry reachability, and imagePullSecrets. Verify Jenkins pushed the image and Argo CD deployed the correct tag."
elif "crashloopbackoff" in lower:
    next_action = "Check the failing container logs, recent app changes, missing environment variables, and config/secret references. Roll back the last GitOps change if needed."
elif "readiness" in lower or "probe" in lower:
    next_action = "Check readiness/liveness probe paths, app startup time, service port mapping, and recent deployment changes."
elif "0/1" in lower or "not ready" in lower:
    next_action = "Inspect pod status, events, and rollout history. Confirm the latest image is healthy and Kubernetes probes are passing."
else:
    next_action = "Review the K8sGPT findings, recent events, pod logs, and the latest Argo CD/Jenkins deployment revision."

payload = {
    "text": f"AI Kubernetes Diagnosis for {namespace}",
    "blocks": [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": "🤖 AI Kubernetes Diagnosis",
                "emoji": True
            }
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*AI-assisted Kubernetes troubleshooting summary for* `{namespace}`"
            }
        },
        {
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": f"*Namespace:*\n`{namespace}`"},
                {"type": "mrkdwn", "text": "*Environment:*\n`local-kind`"},
                {"type": "mrkdwn", "text": f"*AI Backend:*\n`{backend}`"},
                {"type": "mrkdwn", "text": f"*Model:*\n`{model}`"},
                {"type": "mrkdwn", "text": "*Source:*\n`K8sGPT + kubectl`"},
                {"type": "mrkdwn", "text": "*Report:*\n`local file generated`"}
            ]
        },
        {"type": "divider"},
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*🧠 AI Summary / Findings*\n```{analysis_short}```"
            }
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*📌 Evidence*\n*Unhealthy Pods:*\n```{unhealthy_short}```\n*Recent Events:*\n```{events_short}```"
            }
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*✅ Recommended Next Action*\n>{next_action}"
            }
        },
        {
            "type": "actions",
            "elements": [
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "Open Grafana", "emoji": True},
                    "url": "http://grafana.127.0.0.1.nip.io"
                },
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "Open Prometheus", "emoji": True},
                    "url": "http://prometheus.127.0.0.1.nip.io/alerts"
                },
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "Open Alertmanager", "emoji": True},
                    "url": "http://alertmanager.127.0.0.1.nip.io"
                }
            ]
        },
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": f"Generated by *K8sGPT + Ollama* • Report saved locally: `{report_file}`"
                }
            ]
        }
    ]
}

print(json.dumps(payload))
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
