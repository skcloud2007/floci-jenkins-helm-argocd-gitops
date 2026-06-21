# Production-Style Local CI/CD GitOps Platform with Jenkins, Floci, Helm, Argo CD, Monitoring, Slack Alerts, and AI Diagnosis

This project is a production-style local DevOps platform that demonstrates a complete CI/CD and GitOps workflow using Kubernetes, Jenkins, Floci, Helm, Argo CD, Prometheus, Grafana, Alertmanager, Slack alerts, and AI-assisted Kubernetes diagnosis.

Everything runs locally on a kind Kubernetes cluster. No real AWS resources are used.

---

## Project Goal

The goal of this project is to simulate a real-world platform engineering workflow locally:

```text
Developer pushes code
  -> Jenkins builds container image
  -> Image is pushed to local Floci ECR-style registry
  -> Jenkins updates Helm values
  -> Jenkins commits GitOps change
  -> Argo CD syncs Kubernetes deployment
  -> PostSync smoke test validates the deployment
  -> Prometheus scrapes app and Kubernetes metrics
  -> Alertmanager sends Kubernetes alerts to Slack
  -> K8sGPT + Ollama can generate AI diagnosis and next actions
```

---

## Architecture

```text
GitHub Repository
      |
      v
Jenkins Multibranch Pipeline
      |
      | builds image with Kaniko
      v
Floci Local ECR Registry
      |
      | Jenkins updates Helm image tag
      v
GitOps Commit to GitHub
      |
      v
Argo CD
      |
      | syncs Helm chart
      v
kind Kubernetes Cluster
      |
      | app and cluster metrics
      v
Prometheus + Grafana + Alertmanager
      |
      | alerts
      v
Slack Channels
      |
      | optional manual diagnosis
      v
K8sGPT + Ollama AI Diagnosis
```

---

## What This Project Demonstrates

* Local production-style CI/CD pipeline
* GitOps deployment workflow
* Jenkins Multibranch Pipeline with GitHub App authentication
* Kaniko-based image builds inside Kubernetes
* Local AWS/ECR simulation using Floci
* Helm chart packaging
* Argo CD automated sync and self-healing
* Argo CD AppProject isolation
* Argo CD sync waves and PostSync smoke test
* Slack notifications for Jenkins and Argo CD
* Prometheus and Grafana monitoring stack
* Alertmanager Slack routing to `#skm_alerts`
* Application `/metrics` endpoint using `prom-client`
* ServiceMonitor and PrometheusRule integration
* Production-style Kubernetes alert formatting
* Grafana admin credentials stored in Kubernetes Secret
* Slack webhooks stored in Kubernetes Secrets
* K8sGPT + Ollama local AI troubleshooting helper
* Stop/start scripts to preserve local cluster state

---

## Tech Stack

| Area                   | Tool                  |
| ---------------------- | --------------------- |
| Local Kubernetes       | kind                  |
| CI                     | Jenkins               |
| Image Builder          | Kaniko                |
| Local AWS/ECR Emulator | Floci                 |
| Registry               | Floci local registry  |
| Packaging              | Helm                  |
| GitOps                 | Argo CD               |
| Ingress                | ingress-nginx         |
| Monitoring             | kube-prometheus-stack |
| Metrics                | Prometheus            |
| Dashboards             | Grafana               |
| Alerting               | Alertmanager          |
| Notifications          | Slack                 |
| AI Diagnosis           | K8sGPT + Ollama       |
| Runtime App            | Node.js + Express     |

---

## Local URLs

No port-forwarding is required.

| Component    | URL                                  |
| ------------ | ------------------------------------ |
| Jenkins      | http://jenkins.127.0.0.1.nip.io      |
| Argo CD      | http://argocd.127.0.0.1.nip.io       |
| App          | http://myapp.127.0.0.1.nip.io        |
| Grafana      | http://grafana.127.0.0.1.nip.io      |
| Prometheus   | http://prometheus.127.0.0.1.nip.io   |
| Alertmanager | http://alertmanager.127.0.0.1.nip.io |

---

## Repository Structure

```text
.
├── app/
│   ├── Dockerfile
│   ├── package.json
│   ├── package-lock.json
│   └── src/
│       └── server.js
│
├── helm/
│   └── myapp/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           ├── pdb.yaml
│           ├── serviceaccount.yaml
│           ├── servicemonitor.yaml
│           ├── prometheusrule.yaml
│           └── post-sync-smoke-test.yaml
│
├── argocd/
│   ├── appproject.yaml
│   ├── application.yaml
│   ├── monitoring-appproject.yaml
│   └── monitoring-application.yaml
│
├── platform/
│   ├── kind/
│   │   └── kind-config.yaml
│   ├── jenkins/
│   │   ├── values.yaml
│   │   └── floci-registry-docker-config.yaml
│   └── argocd/
│       ├── ingress.yaml
│       └── notifications.yaml
│
├── jenkins/
│   └── Jenkinsfile
│
├── scripts/
│   ├── ai-k8s-diagnose.sh
│   ├── stop-local-stack.sh
│   └── start-local-stack.sh
│
└── README.md
```

---

## Prerequisites

Install these tools on macOS:

```bash
brew install docker kind kubectl helm awscli argocd ollama
```

Verify tools:

```bash
docker --version
kind version
kubectl version --client
helm version
aws --version
argocd version --client
k8sgpt version
ollama list
```

---

## Important: No Real AWS

This project uses Floci locally. Do not use real AWS credentials.

Use these environment variables whenever using AWS CLI with Floci:

```bash
export AWS_ENDPOINT_URL="http://localhost:4566"
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_EC2_METADATA_DISABLED=true
```

Verify local identity:

```bash
aws sts get-caller-identity --endpoint-url "$AWS_ENDPOINT_URL"
```

Expected account:

```json
{
  "UserId": "000000000000",
  "Account": "000000000000",
  "Arn": "arn:aws:iam::000000000000:root"
}
```

---

## kind Cluster

Create the cluster:

```bash
kind create cluster --config platform/kind/kind-config.yaml
kubectl config use-context kind-floci-cicd-gitops
```

Install ingress-nginx:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s
```

---

## Floci Local ECR Registry

Create the local ECR-style repository:

```bash
export ECR_REPOSITORY="floci-cicd/gitops-demo-app"

aws ecr create-repository \
  --repository-name "$ECR_REPOSITORY" \
  --image-scanning-configuration scanOnPush=true \
  --endpoint-url "$AWS_ENDPOINT_URL"
```

Registry values:

```bash
export LOCAL_REGISTRY="localhost:5100"
export K8S_REGISTRY="host.docker.internal:5100"
export IMAGE_NAME="floci-cicd/gitops-demo-app"
```

Configure kind containerd for the local insecure registry:

```bash
docker exec floci-cicd-gitops-control-plane sh -c '
mkdir -p /etc/containerd/certs.d/host.docker.internal:5100

cat > /etc/containerd/certs.d/host.docker.internal:5100/hosts.toml <<EOF_INNER
server = "http://host.docker.internal:5100"

[host."http://host.docker.internal:5100"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF_INNER

systemctl restart containerd
'
```

---

## Demo Application

The app is a Node.js Express service with health, readiness, and Prometheus metrics endpoints.

| Endpoint   | Purpose            |
| ---------- | ------------------ |
| `/`        | App response       |
| `/healthz` | Liveness probe     |
| `/readyz`  | Readiness probe    |
| `/metrics` | Prometheus metrics |

Test:

```bash
curl http://myapp.127.0.0.1.nip.io/
curl http://myapp.127.0.0.1.nip.io/healthz
curl http://myapp.127.0.0.1.nip.io/readyz
curl http://myapp.127.0.0.1.nip.io/metrics | head
```

---

## Jenkins

Jenkins is installed with Helm and exposed through ingress.

URL:

```text
http://jenkins.127.0.0.1.nip.io
```

Local admin:

```text
Username: admin
Password: admin123
```

Jenkins uses:

* Multibranch Pipeline
* GitHub App credentials
* Kaniko Kubernetes build pod
* GitOps commit back to GitHub
* Slack deployment notifications
* `[skip ci]` loop prevention

Pipeline stages:

```text
Checkout
Detect CI Deploy Commit
Prepare Tag
Build and Push Image
Lint Helm Chart
Update Helm Values
Commit GitOps Change
Slack Notification
```

---

## Jenkins Pipeline Flow

```text
Developer push to main
  -> Jenkins detects change
  -> Jenkins builds app image with Kaniko
  -> Image pushed to Floci local registry
  -> Jenkins updates helm/myapp/values.yaml image tag
  -> Jenkins commits: ci: deploy build-XX-sha [skip ci]
  -> Jenkins pushes GitOps commit to main
  -> Argo CD detects Git change
  -> Argo CD syncs app
  -> PostSync smoke test validates /healthz
```

---

## Argo CD

Argo CD is installed in the `argocd` namespace and exposed by ingress.

URL:

```text
http://argocd.127.0.0.1.nip.io
```

Get initial admin password:

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

Check applications:

```bash
kubectl get applications -n argocd
```

Expected:

```text
NAME               SYNC STATUS   HEALTH STATUS
gitops-demo-app    Synced        Healthy
monitoring-stack   Synced        Healthy
```

---

## Argo CD GitOps App

The app is managed by:

```text
argocd/appproject.yaml
argocd/application.yaml
```

Key features:

* Dedicated AppProject
* Automated sync
* Prune enabled
* Self-heal enabled
* Namespace creation enabled
* Helm chart source
* PostSync smoke test
* Slack notifications for deployment success/failure

---

## Argo CD PostSync Smoke Test

The Helm chart includes a PostSync smoke test job:

```text
helm/myapp/templates/post-sync-smoke-test.yaml
```

It validates:

```text
http://myapp.myapp.svc.cluster.local/healthz
```

Check job:

```bash
kubectl get jobs,pods -n myapp
kubectl logs job/myapp-smoke-test -n myapp
```

---

## Slack Notifications

This project uses Slack for three notification types.

| Source                       | Channel                            |
| ---------------------------- | ---------------------------------- |
| Jenkins deployment alerts    | `#jenkins_gitops`                  |
| Argo CD deployment alerts    | configured Argo CD webhook channel |
| Kubernetes/Prometheus alerts | `#skm_alerts`                      |

Secrets are stored in Kubernetes, not Git.

---

## Argo CD Slack Notifications

Argo CD notification config:

```text
platform/argocd/notifications.yaml
```

Webhook Secret:

```bash
kubectl get secret argocd-notifications-secret -n argocd
```

The secret key is:

```text
slack_webhook_url
```

Verify without exposing the secret:

```bash
kubectl get secret argocd-notifications-secret -n argocd \
  -o jsonpath='{.data.slack_webhook_url}' | base64 -d | wc -c
```

---

## Monitoring Stack

Monitoring is installed through Argo CD using `kube-prometheus-stack`.

Files:

```text
argocd/monitoring-appproject.yaml
argocd/monitoring-application.yaml
```

Components:

* Prometheus
* Grafana
* Alertmanager
* kube-state-metrics
* node-exporter
* Prometheus Operator

URLs:

```text
Grafana:      http://grafana.127.0.0.1.nip.io
Prometheus:   http://prometheus.127.0.0.1.nip.io
Alertmanager: http://alertmanager.127.0.0.1.nip.io
```

---

## Grafana Credentials

Grafana credentials are not stored in Git.

They are stored in Kubernetes Secret:

```text
grafana-admin-credentials
```

Get username:

```bash
kubectl get secret grafana-admin-credentials -n monitoring \
  -o jsonpath='{.data.admin-user}' | base64 -d && echo
```

Get password:

```bash
kubectl get secret grafana-admin-credentials -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

---

## Prometheus App Metrics

The application exposes `/metrics` using `prom-client`.

Example metrics:

```text
gitops_demo_app_http_requests_total
gitops_demo_app_http_request_duration_seconds
gitops_demo_app_process_cpu_user_seconds_total
gitops_demo_app_process_resident_memory_bytes
```

Verify:

```bash
curl http://myapp.127.0.0.1.nip.io/metrics | head
```

---

## ServiceMonitor

The app Helm chart includes:

```text
helm/myapp/templates/servicemonitor.yaml
```

Verify:

```bash
kubectl get servicemonitor -n myapp
```

Prometheus query:

```bash
curl -G "http://prometheus.127.0.0.1.nip.io/api/v1/query" \
  --data-urlencode 'query=up{namespace="myapp"}' | python3 -m json.tool
```

Expected value:

```text
1
```

---

## Prometheus Alert Rules

The app Helm chart includes:

```text
helm/myapp/templates/prometheusrule.yaml
```

Alert rules:

| Alert                           | Severity | Purpose                              |
| ------------------------------- | -------- | ------------------------------------ |
| `GitOpsDemoAppUnavailable`      | critical | No available replicas                |
| `GitOpsDemoAppReplicasMismatch` | warning  | Desired replicas not fully available |
| `GitOpsDemoAppPodRestarting`    | warning  | Pod restarted recently               |
| `GitOpsDemoAppTargetDown`       | critical | Prometheus cannot scrape target      |
| `GitOpsDemoAppHigh5xxRate`      | critical | High HTTP 5xx rate                   |

Verify:

```bash
kubectl get prometheusrule -A
kubectl get prometheusrule -n myapp
```

Prometheus alerts page:

```text
http://prometheus.127.0.0.1.nip.io/alerts
```

---

## Alertmanager Slack Alerts

Kubernetes alerts are sent to:

```text
#skm_alerts
```

Webhook Secret:

```bash
kubectl get secret alertmanager-slack-webhook -n monitoring
```

Verify secret length:

```bash
kubectl get secret alertmanager-slack-webhook -n monitoring \
  -o jsonpath='{.data.webhook-url}' | base64 -d | wc -c
```

Alertmanager config is stored in:

```text
argocd/monitoring-application.yaml
```

The Slack alert view includes:

* Alert status
* Severity
* Namespace
* Service
* Team
* Environment
* Grafana button
* Prometheus button
* Alertmanager button

---

## Test Slack Alert

Create a temporary test alert:

```bash
kubectl apply -n myapp -f - <<'YAML'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slack-premium-view-test-alert
  labels:
    release: monitoring
spec:
  groups:
    - name: slack-premium-view-test.rules
      rules:
        - alert: PremiumSlackK8sAlertViewTest
          expr: vector(1)
          for: 30s
          labels:
            severity: critical
            team: platform
            service: gitops-demo-app
          annotations:
            summary: "Premium Kubernetes Slack alert formatting test"
            description: "This verifies clean fields, action buttons, and production-style alert formatting in #skm_alerts."
YAML
```

Delete it after validation:

```bash
kubectl delete prometheusrule slack-premium-view-test-alert -n myapp
```

---

## Real Outage Drill

This project supports a real controlled outage drill.

Pause Argo CD self-heal temporarily:

```bash
kubectl get application gitops-demo-app -n argocd -o yaml > /tmp/gitops-demo-app-before-outage.yaml

kubectl patch application gitops-demo-app -n argocd --type=json \
  -p='[{"op":"remove","path":"/spec/syncPolicy/automated"}]' || true
```

Scale app to zero:

```bash
kubectl scale deployment myapp -n myapp --replicas=0
```

Check alert:

```bash
curl -G "http://prometheus.127.0.0.1.nip.io/api/v1/query" \
  --data-urlencode 'query=ALERTS{alertname="GitOpsDemoAppUnavailable"}' \
  | python3 -m json.tool
```

Recover through GitOps:

```bash
kubectl apply -f argocd/application.yaml

kubectl annotate application gitops-demo-app -n argocd \
  argocd.argoproj.io/refresh=hard \
  --overwrite

kubectl patch application gitops-demo-app -n argocd --type merge -p \
'{"operation":{"sync":{"syncStrategy":{"hook":{}},"prune":true}}}'
```

Verify:

```bash
kubectl rollout status deployment/myapp -n myapp --timeout=300s
curl http://myapp.127.0.0.1.nip.io/
```

---

## AI Kubernetes Diagnosis

This project includes an AI-assisted diagnosis helper:

```text
scripts/ai-k8s-diagnose.sh
```

It uses:

* K8sGPT
* Ollama
* Local LLM model
* kubectl pod status
* Kubernetes events
* pod logs
* Slack Block Kit message

The current local model:

```text
llama3.2:3b
```

Verify Ollama:

```bash
ollama list
```

Configure K8sGPT:

```bash
k8sgpt auth add \
  --backend ollama \
  --model llama3.2:3b \
  --baseurl http://localhost:11434
```

Run diagnosis:

```bash
./scripts/ai-k8s-diagnose.sh myapp
```

Run diagnosis for a specific alert:

```bash
./scripts/ai-k8s-diagnose.sh myapp GitOpsDemoAppUnavailable critical
```

The script posts an AI diagnosis summary to:

```text
#skm_alerts
```

It also creates local debug reports under:

```text
docs/debug/
```

This directory is ignored by Git.

---

## Stop and Start Local Stack

Use these scripts to preserve the cluster state.

Stop stack:

```bash
./scripts/stop-local-stack.sh
```

Start stack later:

```bash
./scripts/start-local-stack.sh
```

These scripts preserve:

* kind cluster container
* Jenkins state
* Argo CD state
* Grafana credentials
* Slack secrets
* Alertmanager secrets
* Floci containers
* monitoring state

Do not use `kind delete cluster` unless you want a full reset.

---

## Useful Commands

Check Argo CD apps:

```bash
kubectl get applications -n argocd
```

Check all pods:

```bash
kubectl get pods -A
```

Check app:

```bash
kubectl get deploy,pods,svc,ingress -n myapp
```

Check monitoring:

```bash
kubectl get pods -n monitoring
kubectl get ingress -n monitoring
```

Check Prometheus rules:

```bash
kubectl get prometheusrule -A
```

Check ServiceMonitor:

```bash
kubectl get servicemonitor -A
```

Check Alertmanager config:

```bash
kubectl exec -n monitoring alertmanager-monitoring-alertmanager-0 \
  -c alertmanager -- \
  cat /etc/alertmanager/config_out/alertmanager.env.yaml
```

Check Jenkins:

```bash
kubectl get pods,svc,ingress -n jenkins
```

Check Argo CD:

```bash
kubectl get pods,svc,ingress -n argocd
```

---

## Security Notes

This project intentionally avoids committing secrets.

Do not commit:

* Slack webhooks
* Grafana passwords
* GitHub App private keys
* Argo CD admin password
* PagerDuty keys
* `.pem` files
* `.env` files
* local debug reports

Secrets are stored in Kubernetes:

| Secret                        | Namespace    | Purpose                        |
| ----------------------------- | ------------ | ------------------------------ |
| `argocd-notifications-secret` | `argocd`     | Argo CD Slack webhook          |
| `alertmanager-slack-webhook`  | `monitoring` | Kubernetes alert Slack webhook |
| `grafana-admin-credentials`   | `monitoring` | Grafana admin credentials      |

---

## Current Production-Style Capabilities

```text
CI/CD:
  Jenkins builds and pushes images with Kaniko

GitOps:
  Argo CD syncs Helm chart and self-heals drift

Registry:
  Floci simulates AWS ECR locally

Deployment Safety:
  Helm readiness/liveness probes
  PDB
  securityContext
  PostSync smoke test

Observability:
  Prometheus metrics
  Grafana dashboards
  ServiceMonitor
  PrometheusRule alerts

Alerting:
  Alertmanager routes Kubernetes alerts to Slack #skm_alerts
  Jenkins sends deployment alerts
  Argo CD sends deployment alerts

AI Diagnosis:
  K8sGPT + Ollama helper summarizes logs/events and suggests next actions
```

---

## Possible Future Enhancements

* Argo Rollouts canary deployment
* Prometheus-based auto rollback analysis
* OneUptime self-hosted incident management
* Automated Alertmanager webhook to trigger AI diagnosis
* Grafana dashboard JSON committed to Git
* SLO and error budget alerts
* GitHub Actions alternative pipeline
* External Secrets integration
* Sealed Secrets or SOPS for GitOps-safe secrets
* Cloudflare Tunnel or Tailscale for secure mobile access

---

## Final End-to-End Flow

```text
Code push
  -> Jenkins pipeline starts
  -> Kaniko builds image
  -> Image pushed to Floci local registry
  -> Jenkins updates Helm values
  -> Jenkins commits GitOps change
  -> Argo CD syncs app
  -> Smoke test validates app
  -> Prometheus scrapes metrics
  -> Alertmanager sends alerts to Slack
  -> K8sGPT + Ollama can generate AI troubleshooting summary
```

This project demonstrates a full local production-style DevOps platform without using real cloud resources.
