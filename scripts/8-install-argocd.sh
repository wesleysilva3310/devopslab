
#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="argocd"
MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

export KUBECONFIG

log() {
    echo
    echo "[$(date '+%H:%M:%S')] $*"
}

fail() {
    echo "ERRO: $*" >&2
    exit 1
}

# Verificações iniciais
command -v kubectl >/dev/null 2>&1 \
    || fail "kubectl não encontrado. Execute no master Kubernetes."

command -v curl >/dev/null 2>&1 \
    || fail "curl não encontrado. Instale-o antes de continuar."

[[ -r "$KUBECONFIG" ]] \
    || fail "Kubeconfig não encontrado em $KUBECONFIG."

kubectl cluster-info >/dev/null 2>&1 \
    || fail "Não foi possível acessar a API do Kubernetes."

echo
echo "=========================================="
echo " Instalação limpa do Argo CD"
echo "=========================================="
echo
echo "ATENÇÃO: a instalação anterior do Argo CD será removida."
echo "Serão excluídos:"
echo " - Namespace argocd e seus recursos"
echo " - CRDs do Argo CD e seus objetos"
echo " - ClusterRoles e ClusterRoleBindings do Argo CD"
echo
echo "Aplicações, projetos e configurações do Argo CD serão perdidos."
echo "Recursos implantados pelo Argo CD em outros namespaces"
echo "não serão removidos automaticamente por este script."
echo

read -r -p "Deseja continuar? Digite 'sim': " confirmation

[[ "$confirmation" == "sim" ]] \
    || fail "Operação cancelada pelo usuário."

# Verificar se o cluster está pronto
log "Aguardando os três nós ficarem Ready..."

for attempt in $(seq 1 60); do
    ready_nodes="$(
        kubectl get nodes --no-headers 2>/dev/null |
            awk '$2 == "Ready" { count++ } END { print count+0 }'
    )"

    if [[ "$ready_nodes" -ge 3 ]]; then
        break
    fi

    if [[ "$attempt" -eq 60 ]]; then
        fail "O cluster não apresentou 3 nós Ready no tempo esperado."
    fi

    sleep 10
done

# Limpeza da instalação anterior
log "Removendo a instalação anterior do Argo CD..."

kubectl delete namespace "$NAMESPACE" \
    --ignore-not-found=true \
    --wait=true \
    --timeout=180s

log "Removendo CRDs do Argo CD..."

kubectl delete crd \
    applicationsets.argoproj.io \
    applications.argoproj.io \
    appprojects.argoproj.io \
    --ignore-not-found=true \
    --wait=true \
    --timeout=180s

log "Removendo ClusterRoles e ClusterRoleBindings do Argo CD..."

kubectl delete clusterrole \
    argocd-application-controller \
    argocd-applicationset-controller \
    argocd-server \
    --ignore-not-found=true

kubectl delete clusterrolebinding \
    argocd-application-controller \
    argocd-applicationset-controller \
    argocd-server \
    --ignore-not-found=true

# Reinstalação
log "Criando namespace ${NAMESPACE}..."

kubectl create namespace "$NAMESPACE"

MANIFEST_FILE="$(mktemp)"
trap 'rm -f "$MANIFEST_FILE"' EXIT

log "Baixando o manifesto oficial do Argo CD..."

curl -fsSL "$MANIFEST_URL" -o "$MANIFEST_FILE" \
    || fail "Não foi possível baixar o manifesto do Argo CD."

log "Instalando o Argo CD com server-side apply..."

kubectl apply \
    --server-side \
    --force-conflicts \
    -n "$NAMESPACE" \
    -f "$MANIFEST_FILE"

# Aguardar componentes
log "Aguardando os Deployments ficarem disponíveis..."

kubectl rollout status deployment \
    --all \
    -n "$NAMESPACE" \
    --timeout=10m

log "Aguardando o Application Controller..."

kubectl rollout status statefulset/argocd-application-controller \
    -n "$NAMESPACE" \
    --timeout=10m

# Resultado
log "Pods do Argo CD:"
kubectl get pods -n "$NAMESPACE" -o wide

log "Serviços do Argo CD:"
kubectl get services -n "$NAMESPACE"

echo
echo "=========================================="
echo " Argo CD instalado com sucesso!"
echo "=========================================="
echo
echo "Namespace: ${NAMESPACE}"
echo "Usuário inicial: admin"
echo
echo "Para acessar via port-forward:"
echo "kubectl port-forward svc/argocd-server -n ${NAMESPACE} 8080:443"
echo
echo "Acesse: https://localhost:8080"
echo

if kubectl get secret argocd-initial-admin-secret \
    -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Senha inicial:"
    kubectl get secret argocd-initial-admin-secret \
        -n "$NAMESPACE" \
        -o go-template='{{.data.password | base64decode}}'
    echo
else
    echo "Secret da senha inicial não encontrado."
    echo "Verifique os pods antes de continuar."
fi
