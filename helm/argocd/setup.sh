#!/usr/bin/env bash
#
# setup-argocd-minikube.sh
# Spins up a local Minikube cluster and installs ArgoCD on it.
#
# Usage:
#   chmod +x setup-argocd-minikube.sh
#   ./setup-argocd-minikube.sh
#
set -euo pipefail

# ---- Config (override via env vars if needed) ----
MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"
MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-8192}"   # MB
MINIKUBE_DRIVER="${MINIKUBE_DRIVER:-docker}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"   # e.g. "stable" or "v3.4.5"
EXPOSE_METHOD="${EXPOSE_METHOD:-port-forward}"  # port-forward | nodeport

log() { echo -e "\n\033[1;32m==> $1\033[0m"; }
err() { echo -e "\033[1;31mERROR: $1\033[0m" >&2; }

# ---- 1. Pre-flight checks ----
log "Checking prerequisites"
for cmd in minikube kubectl; do
  if ! command -v "$cmd" &>/dev/null; then
    err "$cmd is not installed or not in PATH. Install it and re-run."
    exit 1
  fi
done

# ---- 2. Start Minikube ----
log "Starting Minikube (profile: $MINIKUBE_PROFILE, driver: $MINIKUBE_DRIVER)"
if minikube status -p "$MINIKUBE_PROFILE" &>/dev/null; then
  echo "Minikube profile '$MINIKUBE_PROFILE' already running, skipping start."
else
  minikube start \
    -p "$MINIKUBE_PROFILE" \
    --cpus="$MINIKUBE_CPUS" \
    --memory="$MINIKUBE_MEMORY" \
    --driver="$MINIKUBE_DRIVER"
fi

kubectl config use-context "$MINIKUBE_PROFILE"

# ---- 3. Create argocd namespace ----
log "Creating namespace '$ARGOCD_NAMESPACE' (if it doesn't exist)"
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ---- 4. Install ArgoCD ----
log "Installing ArgoCD (version: $ARGOCD_VERSION) into namespace '$ARGOCD_NAMESPACE'"
if [ "$ARGOCD_VERSION" = "stable" ]; then
  MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
else
  MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
fi
kubectl apply -n "$ARGOCD_NAMESPACE" -f "$MANIFEST_URL"

# ---- 5. Wait for pods to be ready ----
log "Waiting for ArgoCD pods to become ready (this can take a few minutes)"
kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=Available deployment --all --timeout=300s || {
  err "Some deployments did not become Available in time. Check with: kubectl get pods -n $ARGOCD_NAMESPACE"
}

# ---- 6. Retrieve the initial admin password ----
log "Fetching initial admin password"
# Newer ArgoCD versions expose this via a Job/CLI; try the secret first, fall back to CLI command.
if kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret &>/dev/null; then
  ADMIN_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
else
  echo "Secret 'argocd-initial-admin-secret' not found yet — it may still be generating."
  echo "Retrieve it later with:"
  echo "  kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  ADMIN_PASSWORD="<not available yet, see command above>"
fi

# ---- 7. Expose the ArgoCD API/UI ----
log "Exposing ArgoCD server (method: $EXPOSE_METHOD)"
if [ "$EXPOSE_METHOD" = "nodeport" ]; then
  kubectl -n "$ARGOCD_NAMESPACE" patch svc argocd-server -p '{"spec": {"type": "NodePort"}}'
  ARGOCD_URL="https://$(minikube -p "$MINIKUBE_PROFILE" ip):$(kubectl -n "$ARGOCD_NAMESPACE" get svc argocd-server -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}')"
  echo "ArgoCD UI available at: $ARGOCD_URL"
else
  echo "Run this in a separate terminal to access the UI:"
  echo "  kubectl -n $ARGOCD_NAMESPACE port-forward svc/argocd-server 8080:443"
  echo "Then open: https://localhost:8080"
fi

# ---- 8. Summary ----
log "ArgoCD setup complete"
cat <<EOF

Namespace:      $ARGOCD_NAMESPACE
Username:       admin
Password:       $ADMIN_PASSWORD

Login via CLI (requires 'argocd' CLI installed):
  argocd login localhost:8080 --username admin --password '$ADMIN_PASSWORD' --insecure

Check pod status:
  kubectl get pods -n $ARGOCD_NAMESPACE

EOF