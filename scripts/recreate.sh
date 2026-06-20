#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-floci-cicd-gitops}"
AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
AWS_EC2_METADATA_DISABLED="${AWS_EC2_METADATA_DISABLED:-true}"

export AWS_ENDPOINT_URL AWS_REGION AWS_DEFAULT_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_EC2_METADATA_DISABLED

echo "Recreating local Jenkins + Floci + Helm + Argo CD GitOps platform..."

echo "Checking Floci..."
floci doctor || true

echo "Creating kind cluster..."
if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  echo "kind cluster $CLUSTER_NAME already exists."
else
  kind create cluster --config platform/kind/kind-config.yaml
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

echo "Installing ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo "Configuring kind containerd for local Floci registry..."
docker exec "${CLUSTER_NAME}-control-plane" sh -c '
mkdir -p /etc/containerd/certs.d/host.docker.internal:5100

cat > /etc/containerd/certs.d/host.docker.internal:5100/hosts.toml <<REGISTRYEOF
server = "http://host.docker.internal:5100"

[host."http://host.docker.internal:5100"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
REGISTRYEOF

systemctl restart containerd
'

echo "Creating Floci ECR repository if missing..."
aws ecr describe-repositories \
  --repository-names floci-cicd/gitops-demo-app \
  --endpoint-url "$AWS_ENDPOINT_URL" >/dev/null 2>&1 || \
aws ecr create-repository \
  --repository-name floci-cicd/gitops-demo-app \
  --image-scanning-configuration scanOnPush=true \
  --endpoint-url "$AWS_ENDPOINT_URL"

echo "Building and pushing initial image..."
docker build -f app/Dockerfile -t gitops-demo-app:local app
docker tag gitops-demo-app:local localhost:5100/floci-cicd/gitops-demo-app:v1.0.0
docker push localhost:5100/floci-cicd/gitops-demo-app:v1.0.0

echo "Installing Jenkins..."
helm repo add jenkins https://charts.jenkins.io >/dev/null 2>&1 || true
helm repo update

kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install jenkins jenkins/jenkins \
  -n jenkins \
  -f platform/jenkins/values.yaml

kubectl rollout status statefulset/jenkins -n jenkins --timeout=300s

echo "Applying Jenkins registry ConfigMap..."
kubectl apply -f platform/jenkins/floci-registry-docker-config.yaml

echo "Installing Argo CD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply --server-side=true -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || \
kubectl apply --server-side=true --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

echo "Patching Argo CD for HTTP ingress..."
kubectl patch configmap argocd-cmd-params-cm \
  -n argocd \
  --type merge \
  -p '{"data":{"server.insecure":"true"}}'

kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

kubectl apply -f platform/argocd/ingress.yaml

echo "Deploying app with Helm initial state..."
helm upgrade --install myapp helm/myapp \
  -n myapp \
  --create-namespace

kubectl rollout status deployment/myapp -n myapp --timeout=300s

echo "Applying Argo CD Application..."
kubectl apply -f argocd/application.yaml

echo "Recreate complete."
echo
echo "Jenkins: http://jenkins.127.0.0.1.nip.io"
echo "Argo CD: http://argocd.127.0.0.1.nip.io"
echo "App:     http://myapp.127.0.0.1.nip.io"
echo
echo "Argo CD admin password:"
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true
echo
