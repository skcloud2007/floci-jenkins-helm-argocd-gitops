# Production-Style Local CI/CD GitOps Pipeline with Jenkins, Floci ECR, Helm, Argo CD, Slack, and kind

![Project Status](https://img.shields.io/badge/status-working-brightgreen)
![Kubernetes](https://img.shields.io/badge/kubernetes-kind-blue)
![CI](https://img.shields.io/badge/CI-Jenkins-red)
![GitOps](https://img.shields.io/badge/GitOps-Argo%20CD-orange)
![Registry](https://img.shields.io/badge/Registry-Floci%20ECR-purple)
![Notifications](https://img.shields.io/badge/Slack-enabled-4A154B)

## Overview

This project demonstrates a production-style CI/CD and GitOps workflow running completely on a local machine.

It uses Jenkins for CI, Kaniko for container image builds inside Kubernetes, Floci as a local AWS ECR-style registry, Helm for Kubernetes packaging, Argo CD for GitOps deployment, kind for the local Kubernetes cluster, ingress-nginx for browser access without port-forwarding, and Slack for deployment notifications.

The complete flow is:

```text
GitHub source change
→ Jenkins Multibranch Pipeline
→ Kubernetes Jenkins agent
→ Kaniko image build
→ Floci ECR-style local registry
→ Jenkins updates Helm values.yaml
→ Jenkins pushes GitOps commit
→ Argo CD auto-syncs
→ kind Kubernetes rollout
→ Slack receives deployment status
```

## Key Features

* Local production-style CI/CD pipeline without real AWS cost
* Jenkins exposed through ingress, no port-forwarding required
* Argo CD exposed through ingress, no port-forwarding required
* Floci used as a local AWS/ECR-style service emulator
* Kaniko builds images inside Kubernetes without Docker-in-Docker
* Helm chart manages Kubernetes deployment, service, ingress, probes, security context, and PDB
* Argo CD automatically reconciles Kubernetes state from Git
* Jenkins GitHub App integration for repository access
* Slack Block Kit notifications with build status and image URI
* CI loop prevention using `[skip ci]`
* Local kind cluster configured with ingress ports 80 and 443

## Repository Structure

```text
.
├── Jenkinsfile
├── README.md
├── app
│   ├── Dockerfile
│   ├── package.json
│   └── src
│       └── server.js
├── argocd
│   └── application.yaml
├── docs
│   ├── linkedin-post.md
│   └── screenshots
├── helm
│   └── myapp
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           ├── ingress.yaml
│           ├── pdb.yaml
│           ├── service.yaml
│           └── serviceaccount.yaml
├── jenkins
│   └── Jenkinsfile
├── platform
│   ├── argocd
│   │   └── ingress.yaml
│   ├── jenkins
│   │   ├── floci-registry-docker-config.yaml
│   │   └── values.yaml
│   └── kind
│       └── kind-config.yaml
└── scripts
    ├── cleanup.sh
    └── recreate.sh
```

## Architecture Diagram

```mermaid
flowchart LR
    Dev[Developer] -->|git push| GitHub[GitHub Repository]

    GitHub -->|branch scan / checkout| Jenkins[Jenkins Multibranch Pipeline]

    Jenkins --> Agent[Kubernetes Jenkins Agent Pod]

    Agent --> Tools[tools container<br/>helm git yq curl]
    Agent --> Kaniko[kaniko container<br/>build image]

    Kaniko -->|push image| Floci[Floci ECR-style Registry<br/>host.docker.internal:5100]

    Tools -->|update image tag| HelmValues[helm/myapp/values.yaml]
    Tools -->|git commit + push| GitHub

    GitHub -->|desired state| ArgoCD[Argo CD Application]

    ArgoCD -->|sync Helm chart| Kind[kind Kubernetes Cluster]

    Kind --> MyApp[gitops-demo-app Deployment]
    MyApp --> Ingress[ingress-nginx]
    Ingress --> Browser[http://myapp.127.0.0.1.nip.io]

    Jenkins -->|success/failure Block Kit alert| Slack[#jenkins_gitops]
```

## Tech Stack

| Component                 | Purpose                                              |
| ------------------------- | ---------------------------------------------------- |
| Docker Desktop            | Container runtime                                    |
| kind                      | Local Kubernetes cluster                             |
| kubectl                   | Kubernetes CLI                                       |
| Helm                      | Kubernetes package manager                           |
| Jenkins                   | CI pipeline engine                                   |
| Jenkins Kubernetes Plugin | Dynamic build agents in Kubernetes                   |
| Kaniko                    | Container image build and push without Docker daemon |
| Floci                     | Local AWS/ECR-style emulator                         |
| Argo CD                   | GitOps continuous delivery                           |
| ingress-nginx             | HTTP ingress for local services                      |
| Slack Incoming Webhook    | Deployment notifications                             |
| GitHub App                | Jenkins authentication to GitHub                     |

## Local URLs

| Service  | URL                             |
| -------- | ------------------------------- |
| Jenkins  | http://jenkins.127.0.0.1.nip.io |
| Argo CD  | http://argocd.127.0.0.1.nip.io  |
| Demo App | http://myapp.127.0.0.1.nip.io   |

## Prerequisites

Install the following tools:

```bash
docker --version
kind version
kubectl version --client
helm version
aws --version
floci --version
```

Expected local setup:

```text
Docker Desktop
kind
kubectl
helm
AWS CLI
Floci
GitHub account
Slack workspace
```

## Environment Variables for Floci

This project uses Floci instead of real AWS.

Use these environment variables whenever interacting with AWS CLI for local Floci services:

```bash
export AWS_ENDPOINT_URL="http://localhost:4566"
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_EC2_METADATA_DISABLED=true
```

Verify Floci:

```bash
floci doctor

aws sts get-caller-identity \
  --endpoint-url "$AWS_ENDPOINT_URL"
```

Expected account:

```json
{
  "UserId": "000000000000",
  "Account": "000000000000",
  "Arn": "arn:aws:iam::000000000000:root"
}
```

## kind Cluster

The cluster is created with host ports 80 and 443 mapped into ingress-nginx.

```bash
kind create cluster --config platform/kind/kind-config.yaml
kubectl config use-context kind-floci-cicd-gitops
```

Verify:

```bash
kubectl get nodes
```

## Install ingress-nginx

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s
```

Verify:

```bash
kubectl get pods -n ingress-nginx
```

## Floci ECR-Style Registry

Create local ECR repository:

```bash
export ECR_REPOSITORY="floci-cicd/gitops-demo-app"

aws ecr create-repository \
  --repository-name "$ECR_REPOSITORY" \
  --image-scanning-configuration scanOnPush=true \
  --endpoint-url "$AWS_ENDPOINT_URL"
```

For this project, Docker pushes to:

```text
localhost:5100/floci-cicd/gitops-demo-app
```

Kubernetes pulls from:

```text
host.docker.internal:5100/floci-cicd/gitops-demo-app
```

Configure kind containerd to allow the local HTTP registry:

```bash
docker exec floci-cicd-gitops-control-plane sh -c '
mkdir -p /etc/containerd/certs.d/host.docker.internal:5100

cat > /etc/containerd/certs.d/host.docker.internal:5100/hosts.toml <<EOF
server = "http://host.docker.internal:5100"

[host."http://host.docker.internal:5100"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF

systemctl restart containerd
'
```

## Build and Push Initial Image

```bash
export LOCAL_REGISTRY="localhost:5100"
export IMAGE_NAME="floci-cicd/gitops-demo-app"
export IMAGE_TAG="v1.0.0"

export LOCAL_IMAGE_URI="${LOCAL_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker build -f app/Dockerfile -t gitops-demo-app:local app
docker tag gitops-demo-app:local "$LOCAL_IMAGE_URI"
docker push "$LOCAL_IMAGE_URI"
```

Verify:

```bash
docker pull "$LOCAL_IMAGE_URI"
```

## Deploy App with Helm

```bash
helm lint helm/myapp

helm upgrade --install myapp helm/myapp \
  -n myapp \
  --create-namespace

kubectl rollout status deployment/myapp -n myapp
```

Verify:

```bash
curl http://myapp.127.0.0.1.nip.io
```

Expected response:

```json
{
  "app": "gitops-demo-app",
  "message": "Hello from Jenkins + Floci ECR + Helm + Argo CD",
  "version": "v1.0.0",
  "status": "running"
}
```

## Jenkins Setup

Install Jenkins using Helm:

```bash
helm repo add jenkins https://charts.jenkins.io
helm repo update

kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install jenkins jenkins/jenkins \
  -n jenkins \
  -f platform/jenkins/values.yaml
```

Wait for Jenkins:

```bash
kubectl rollout status statefulset/jenkins -n jenkins --timeout=300s
```

Jenkins URL:

```text
http://jenkins.127.0.0.1.nip.io
```

Default local login used in this project:

```text
Username: admin
Password: admin123
```

## Jenkins Registry ConfigMap

Apply the Kaniko Docker config:

```bash
kubectl apply -f platform/jenkins/floci-registry-docker-config.yaml
```

## GitHub App for Jenkins

Create a GitHub App and install it only on this repository.

Required permissions:

```text
Repository permissions:
- Contents: Read and write
- Metadata: Read-only
- Commit statuses: Read and write
```

Optional:

```text
- Checks: Read and write
```

If Jenkins rejects the private key, convert it to PKCS#8:

```bash
openssl pkcs8 \
  -topk8 \
  -inform PEM \
  -outform PEM \
  -in your-github-app-private-key.pem \
  -out github-app-pkcs8.pem \
  -nocrypt
```

Verify:

```bash
head -1 github-app-pkcs8.pem
```

Expected:

```text
-----BEGIN PRIVATE KEY-----
```

Create Jenkins credential:

```text
Kind: GitHub App
ID: github-app
App ID: <your GitHub App ID>
Private Key: <PKCS#8 private key>
```

## Jenkins Multibranch Pipeline

Create a Jenkins Multibranch Pipeline:

```text
Name: floci-gitops-pipeline
Branch Source: GitHub
Credentials: github-app
Repository HTTPS URL: https://github.com/skcloud2007/floci-jenkins-helm-argocd-gitops
Build configuration: by Jenkinsfile
Script Path: jenkins/Jenkinsfile
```

Behaviors:

```text
Discover branches: All branches
```

Recommended local scan interval:

```text
Periodically if not otherwise run: 5 minutes or 15 minutes
```

## Argo CD Setup

Install Argo CD:

```bash
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply --server-side=true -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Patch Argo CD server for local HTTP ingress:

```bash
kubectl patch configmap argocd-cmd-params-cm \
  -n argocd \
  --type merge \
  -p '{"data":{"server.insecure":"true"}}'

kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
```

Apply ingress:

```bash
kubectl apply -f platform/argocd/ingress.yaml
```

Argo CD URL:

```text
http://argocd.127.0.0.1.nip.io
```

Get admin password:

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

Apply Argo CD Application:

```bash
kubectl apply -f argocd/application.yaml
```

Verify:

```bash
kubectl get applications -n argocd
```

Expected:

```text
NAME              SYNC STATUS   HEALTH STATUS
gitops-demo-app   Synced        Healthy
```

## Slack Notifications

Create Slack channel:

```text
#jenkins_gitops
```

Create Slack Incoming Webhook for that channel.

Add Jenkins credential:

```text
Kind: Secret text
ID: slack-webhook-url
Secret: <Slack Incoming Webhook URL>
Description: Slack webhook for Jenkins GitOps notifications
```

The Jenkins pipeline sends rich Slack Block Kit messages containing:

```text
Build status
Job name
Build number
Branch
Commit
Commit author
Image URI
Argo CD app
Application URL
Jenkins build URL
```

Example image field:

```text
host.docker.internal:5100/floci-cicd/gitops-demo-app:build-22-322057d
```

## End-to-End Test

Make a source code change:

```bash
perl -pi -e 's/Hello from Jenkins/Hello from Jenkins GitOps pipeline/g' app/src/server.js

git add app/src/server.js
git commit -m "Test end-to-end Jenkins GitOps pipeline"

git pull --rebase origin main
git push origin main
```

Trigger Jenkins:

```text
Jenkins → floci-gitops-pipeline → Scan Repository Now
```

Expected Jenkins stages:

```text
Checkout
Detect CI Deploy Commit
Prepare Tag
Build and Push Image
Lint Helm Chart
Update Helm Values
Commit GitOps Change
```

Verify GitOps commit:

```bash
git pull origin main
git log --oneline -5
grep -A 4 '^image:' helm/myapp/values.yaml
```

Verify Argo CD rollout:

```bash
kubectl get applications -n argocd
kubectl rollout status deployment/myapp -n myapp
kubectl get pods -n myapp
curl http://myapp.127.0.0.1.nip.io
```

Expected response contains the new build tag:

```json
{
  "version": "build-..."
}
```

## Screenshot Guide

Add screenshots under:

```text
docs/screenshots/
```

Recommended screenshots:

```text
docs/screenshots/01-architecture.png
docs/screenshots/02-jenkins-dashboard.png
docs/screenshots/03-jenkins-successful-build.png
docs/screenshots/04-argocd-healthy-app.png
docs/screenshots/05-app-response.png
docs/screenshots/06-slack-success-alert.png
docs/screenshots/07-floci-ecr-repository.png
```

Then update this section:

### Jenkins Multibranch Pipeline

![Jenkins Pipeline](docs/screenshots/03-jenkins-successful-build.png)

### Argo CD Healthy Application

![Argo CD App](docs/screenshots/04-argocd-healthy-app.png)

### Slack Deployment Notification

![Slack Alert](docs/screenshots/06-slack-success-alert.png)

### Demo App Response

![App Response](docs/screenshots/05-app-response.png)

## Troubleshooting

### Jenkins scans but does not discover main branch

Check Jenkins branch discovery behavior.

Correct setting:

```text
Discover branches → Strategy: All branches
```

Incorrect setting:

```text
Only branches that are also filed as PRs
```

### Jenkins says private key must be PKCS#8

Convert the GitHub App private key:

```bash
openssl pkcs8 \
  -topk8 \
  -inform PEM \
  -outform PEM \
  -in current-key.pem \
  -out github-app-pkcs8.pem \
  -nocrypt
```

### Jenkins cannot push to GitHub

Check GitHub App permissions:

```text
Contents: Read and write
Metadata: Read-only
```

Also make sure the GitHub App is installed on the repository.

### Jenkins cannot update GitHub commit status

Add GitHub App permission:

```text
Commit statuses: Read and write
```

Then update the app installation access.

### Kaniko cannot push to registry

Verify Floci registry is running:

```bash
docker ps | grep floci
```

Expected registry port:

```text
0.0.0.0:5100->5000/tcp
```

Verify Jenkins ConfigMap:

```bash
kubectl get configmap floci-registry-docker-config -n jenkins -o yaml
```

### Kubernetes pod cannot pull image from Floci registry

If pod shows:

```text
http: server gave HTTP response to HTTPS client
```

Configure kind containerd:

```bash
docker exec floci-cicd-gitops-control-plane sh -c '
mkdir -p /etc/containerd/certs.d/host.docker.internal:5100

cat > /etc/containerd/certs.d/host.docker.internal:5100/hosts.toml <<EOF
server = "http://host.docker.internal:5100"

[host."http://host.docker.internal:5100"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF

systemctl restart containerd
'
```

### Argo CD UI redirects to HTTPS or fails through ingress

Patch Argo CD server insecure mode:

```bash
kubectl patch configmap argocd-cmd-params-cm \
  -n argocd \
  --type merge \
  -p '{"data":{"server.insecure":"true"}}'

kubectl rollout restart deployment/argocd-server -n argocd
```

### Slack message is not received

Check Jenkins credential:

```text
ID: slack-webhook-url
Kind: Secret text
```

Test webhook manually:

```bash
curl -X POST \
  -H 'Content-type: application/json' \
  --data '{"text":"Slack webhook test"}' \
  '<your-webhook-url>'
```

Expected response:

```text
ok
```

### Jenkins builds repeatedly every scan

The Jenkinsfile includes CI loop prevention.

Jenkins deploy commits use:

```text
ci: deploy <image-tag> [skip ci]
```

The pipeline detects these commits and skips build/push stages.

## Useful Commands

Check all project namespaces:

```bash
kubectl get pods -A
```

Check app:

```bash
kubectl get all -n myapp
kubectl get ingress -n myapp
curl http://myapp.127.0.0.1.nip.io
```

Check Jenkins:

```bash
kubectl get pods -n jenkins
kubectl get ingress -n jenkins
```

Check Argo CD:

```bash
kubectl get pods -n argocd
kubectl get applications -n argocd
```

Check Floci:

```bash
floci doctor
docker ps | grep floci
```

Check image tags in registry:

```bash
curl http://localhost:5100/v2/floci-cicd/gitops-demo-app/tags/list
```

## Cleanup

Run:

```bash
./scripts/cleanup.sh
```

## Recreate

Run:

```bash
./scripts/recreate.sh
```

## LinkedIn Post

```text
🚀 Built a production-style local CI/CD + GitOps pipeline using Jenkins, Floci ECR, Helm, Argo CD, Slack, and kind.

This project simulates a real-world cloud-native delivery workflow without using real AWS resources or incurring cloud cost.

The flow:

GitHub source change
→ Jenkins Multibranch Pipeline
→ Kubernetes Jenkins agent
→ Kaniko builds container image
→ Image pushed to Floci ECR-style local registry
→ Jenkins updates Helm values.yaml
→ Jenkins pushes GitOps commit
→ Argo CD auto-syncs
→ kind Kubernetes rollout
→ Slack receives deployment notification

Key highlights:

✅ Jenkins running on Kubernetes
✅ Dynamic Jenkins build agents
✅ Kaniko-based image builds without Docker-in-Docker
✅ Local ECR-style registry with Floci
✅ Helm-based Kubernetes deployment
✅ Argo CD GitOps auto-sync
✅ ingress-nginx access without port-forwarding
✅ Slack Block Kit deployment alerts
✅ GitHub App authentication
✅ CI loop prevention with [skip ci]

This was a great hands-on project to connect CI, container builds, registry workflows, Helm, GitOps, Kubernetes, and notifications into one complete delivery platform.

#DevOps #Kubernetes #Jenkins #ArgoCD #GitOps #Helm #CI/CD #PlatformEngineering #CloudNative #Slack #Docker
```

## What This Project Demonstrates

This project demonstrates practical skills in:

```text
CI/CD pipeline design
GitOps workflows
Kubernetes application delivery
Helm chart authoring
Container image build automation
Local cloud service emulation
Jenkins Kubernetes agents
GitHub App authentication
Slack notification integration
Troubleshooting real DevOps pipeline failures
```

## Final Result

The final platform behaves like a lightweight local version of a real enterprise delivery system:

```text
Developer pushes code
Jenkins builds and publishes image
GitOps repo state changes
Argo CD reconciles Kubernetes
Slack receives a deployment alert
Application updates through ingress
```

No real AWS account is required.
No cloud bill is created.
No port-forwarding is required for Jenkins, Argo CD, or the application.
