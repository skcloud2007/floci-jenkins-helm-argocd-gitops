#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-myapp}"
ALERT_NAME="${2:-ManualAIDiagnosis}"
SEVERITY="${3:-info}"
BACKEND="${K8SGPT_BACKEND:-ollama}"
MODEL="${K8SGPT_MODEL:-llama3.2:3b}"
ENVIRONMENT="${ENVIRONMENT:-local-kind}"
REPORT_DIR="docs/debug"
REPORT_FILE="${REPORT_DIR}/ai-k8s-diagnosis-${NAMESPACE}-$(date +%Y%m%d-%H%M%S).txt"

mkdir -p "$REPORT_DIR"

echo "Running AI Kubernetes diagnosis..."
echo "Namespace: ${NAMESPACE}"
echo "Alert: ${ALERT_NAME}"
echo "Severity: ${SEVERITY}"
echo "Backend: ${BACKEND}"
echo "Model: ${MODEL}"

{
  echo "===== AI Kubernetes Diagnosis ====="
  echo "Date: $(date)"
  echo "Namespace: ${NAMESPACE}"
  echo "Alert: ${ALERT_NAME}"
  echo "Severity: ${SEVERITY}"
  echo "Environment: ${ENVIRONMENT}"
  echo "Backend: ${BACKEND}"
  echo "Model: ${MODEL}"
  echo

  echo "===== Deployment Health ====="
  kubectl get deploy -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas,AVAILABLE:.status.availableReplicas,UPDATED:.status.updatedReplicas' \
    2>/dev/null || true
  echo

  echo "===== Pod Health ====="
  kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || true
  echo

  echo "===== Pod Restart Summary ====="
  kubectl get pods -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount,READY:.status.containerStatuses[*].ready' \
    2>/dev/null || true
  echo

  echo "===== Unhealthy Pods ====="
  unhealthy="$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" {print $0}' || true)"
  if [ -n "$unhealthy" ]; then
    echo "$unhealthy"
  else
    echo "No unhealthy pods detected."
  fi
  echo

  echo "===== Warning Events ====="
  events="$(kubectl get events -n "$NAMESPACE" --field-selector type!=Normal --sort-by='.lastTimestamp' 2>/dev/null | tail -30 || true)"
  if [ -n "$events" ]; then
    echo "$events"
  else
    echo "No warning events found."
  fi
  echo

  echo "===== Recent Pod Logs ====="
  pods="$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}' | head -5 || true)"
  if [ -n "$pods" ]; then
    for pod in $pods; do
      echo
      echo "----- Pod: ${pod} -----"
      kubectl logs "$pod" -n "$NAMESPACE" --tail=60 --all-containers=true 2>/dev/null || true
    done
  else
    echo "No pods found."
  fi
  echo

  echo "===== K8sGPT Analysis ====="
  k8sgpt analyze --namespace "$NAMESPACE" --explain --backend "$BACKEND" 2>/dev/null || true
} | tee "$REPORT_FILE"

SLACK_WEBHOOK_URL="$(kubectl get secret alertmanager-slack-webhook \
  -n monitoring \
  -o jsonpath='{.data.webhook-url}' | base64 -d)"

export NAMESPACE ALERT_NAME SEVERITY BACKEND MODEL ENVIRONMENT REPORT_FILE

PAYLOAD="$(python3 - <<'PY'
import json
import os
import re
from pathlib import Path

namespace = os.environ["NAMESPACE"]
alert_name = os.environ["ALERT_NAME"]
severity = os.environ["SEVERITY"]
backend = os.environ["BACKEND"]
model = os.environ["MODEL"]
environment = os.environ["ENVIRONMENT"]
report_file = os.environ["REPORT_FILE"]

report = Path(report_file).read_text(errors="ignore")

def section(title, next_title=None):
    start = f"===== {title} ====="
    if start not in report:
        return ""
    part = report.split(start, 1)[1]
    if next_title:
        end = f"===== {next_title} ====="
        if end in part:
            part = part.split(end, 1)[0]
    return part.strip()

deployment_health = section("Deployment Health", "Pod Health")
pod_health = section("Pod Health", "Pod Restart Summary")
restart_summary = section("Pod Restart Summary", "Unhealthy Pods")
unhealthy = section("Unhealthy Pods", "Warning Events")
events = section("Warning Events", "Recent Pod Logs")
logs = section("Recent Pod Logs", "K8sGPT Analysis")
k8sgpt = section("K8sGPT Analysis")

noise_patterns = [
    "kube-root-ca.crt",
    "ConfigMap kube-root-ca.crt is not used",
    "not used by any pods in the namespace",
]

def strip_noise(text):
    if not text.strip():
        return ""
    if all(p.lower() in text.lower() for p in ["kube-root-ca.crt", "not used"]):
        return ""
    lines = []
    for line in text.splitlines():
        if any(p.lower() in line.lower() for p in noise_patterns):
            continue
        lines.append(line)
    cleaned = "\n".join(lines).strip()
    if cleaned.lower() in {"ai provider: ollama", "ai provider: openai"}:
        return ""
    return cleaned

k8sgpt_clean = strip_noise(k8sgpt)

combined = f"{deployment_health}\n{pod_health}\n{restart_summary}\n{unhealthy}\n{events}\n{logs}\n{k8sgpt_clean}".lower()

issue_keywords = {
    "ImagePullBackOff": ["imagepullbackoff", "errimagepull", "pull access denied", "manifest unknown"],
    "CrashLoopBackOff": ["crashloopbackoff", "back-off restarting failed container"],
    "ProbeFailure": ["readiness probe failed", "liveness probe failed", "probe failed"],
    "UnavailableReplicas": ["<none>", "0/", "unavailable", "no available replicas"],
    "ConfigOrSecretIssue": ["secret not found", "configmap not found", "couldn't find key", "not found"],
    "SchedulingIssue": ["failedscheduling", "insufficient cpu", "insufficient memory", "node(s) had taint"],
}

issue_type = "No active issue detected"
for name, keys in issue_keywords.items():
    if any(k in combined for k in keys):
        issue_type = name
        break

has_unhealthy = unhealthy.strip() and "No unhealthy pods detected." not in unhealthy
has_warning_events = events.strip() and "No warning events found." not in events
has_real_k8sgpt = bool(k8sgpt_clean)

if issue_type != "No active issue detected" or has_unhealthy or has_warning_events or has_real_k8sgpt:
    verdict = "Needs Attention"
    header_emoji = "🚨" if severity == "critical" else "⚠️"
    color_word = "warning"
else:
    verdict = "Healthy"
    header_emoji = "✅"
    color_word = "good"

if issue_type == "ImagePullBackOff":
    next_action = "Verify the image tag in Helm values, confirm Jenkins pushed the image to Floci registry, and check Kubernetes can pull from host.docker.internal:5100."
elif issue_type == "CrashLoopBackOff":
    next_action = "Inspect the latest container logs, check recent code/config changes, and roll back the last GitOps deployment if the new image is broken."
elif issue_type == "ProbeFailure":
    next_action = "Check readiness/liveness probe paths, service targetPort, app startup time, and whether /healthz and /readyz return HTTP 200."
elif issue_type == "UnavailableReplicas":
    next_action = "Check deployment rollout status, pod scheduling, image pull status, and recent Argo CD sync revision."
elif issue_type == "ConfigOrSecretIssue":
    next_action = "Verify referenced ConfigMaps, Secrets, environment variables, and volume mounts exist in the namespace."
elif issue_type == "SchedulingIssue":
    next_action = "Check node capacity, pod resource requests/limits, taints, tolerations, and pending pod events."
elif verdict == "Healthy":
    next_action = "No immediate action required. Namespace appears healthy. Continue monitoring dashboards and alerts."
else:
    next_action = "Review the evidence below, compare with the latest Jenkins build and Argo CD revision, then inspect affected pod logs/events."

def trim(text, limit):
    text = text.strip()
    if not text:
        return "None"
    return text[:limit]

if verdict == "Healthy":
    ai_summary = "No actionable Kubernetes issue detected. K8sGPT only returned non-critical/noisy findings or no findings."
else:
    ai_summary = k8sgpt_clean or "K8sGPT did not return a specific root cause. Evidence from Kubernetes events/pods suggests investigation is required."

evidence = []
if has_unhealthy:
    evidence.append(f"*Unhealthy Pods:*\n```{trim(unhealthy, 900)}```")
if has_warning_events:
    evidence.append(f"*Warning Events:*\n```{trim(events, 1200)}```")
if not evidence:
    evidence.append("*Cluster Evidence:*\n```No unhealthy pods or warning events found in this namespace.```")

payload = {
    "text": f"{header_emoji} AI Kubernetes Diagnosis - {namespace} - {verdict}",
    "blocks": [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": f"{header_emoji} AI Kubernetes Diagnosis",
                "emoji": True
            }
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*{namespace}* analysis completed with verdict: *{verdict}*"
            }
        },
        {
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": f"*Alert:*\n`{alert_name}`"},
                {"type": "mrkdwn", "text": f"*Verdict:*\n`{verdict}`"},
                {"type": "mrkdwn", "text": f"*Namespace:*\n`{namespace}`"},
                {"type": "mrkdwn", "text": f"*Severity:*\n`{severity}`"},
                {"type": "mrkdwn", "text": f"*Issue Type:*\n`{issue_type}`"},
                {"type": "mrkdwn", "text": f"*Environment:*\n`{environment}`"},
                {"type": "mrkdwn", "text": f"*AI Backend:*\n`{backend}`"},
                {"type": "mrkdwn", "text": f"*Model:*\n`{model}`"}
            ]
        },
        {"type": "divider"},
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*🧠 Smart Summary*\n```{trim(ai_summary, 1600)}```"
            }
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "*📌 Evidence*\n" + "\n".join(evidence)
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
                    "text": f"K8sGPT + Ollama • Report: `{report_file}`"
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
echo "Smart AI diagnosis posted to Slack #skm_alerts."
