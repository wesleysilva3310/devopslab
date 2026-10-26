
#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="argocd"
HOST="argocd.lab"
TLS_SECRET="argocd-tls"
CLUSTER_ISSUER="lab-ca-issuer"

log() {
    echo
    echo "[$(date '+%H:%M:%S')] $*"
}

fail() {
    echo "ERRO: $*" >&2
    exit 1
}

command -v kubectl >/dev/null 2>&1 \
    || fail "kubectl não encontrado."

kubectl cluster-info >/dev/null 2>&1 \
    || fail "Não foi possível acessar o cluster Kubernetes."

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 \
    || fail "Namespace argocd não encontrado. Instale o Argo CD primeiro."

kubectl get ingressclass nginx >/dev/null 2>&1 \
    || fail "IngressClass nginx não encontrada."

kubectl get clusterissuer "$CLUSTER_ISSUER" >/dev/null 2>&1 \
    || fail "ClusterIssuer $CLUSTER_ISSUER não encontrado."

log "Configurando Ingress para https://${HOST}..."

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: ${NAMESPACE}
  annotations:
    cert-manager.io/cluster-issuer: ${CLUSTER_ISSUER}
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - ${HOST}
      secretName: ${TLS_SECRET}
  rules:
    - host: ${HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 443
EOF

log "Aguardando o certificado TLS..."

if ! kubectl wait \
    --for=condition=Ready \
    "certificate/${TLS_SECRET}" \
    -n "$NAMESPACE" \
    --timeout=180s; then
    echo "AVISO: o certificado ainda não está Ready."
    echo "Consulte: kubectl describe certificate ${TLS_SECRET} -n ${NAMESPACE}"
    echo "E: kubectl get certificaterequest,order,challenge -n ${NAMESPACE}"
    exit 1
fi

log "Ingress configurado:"
kubectl get ingress argocd-server -n "$NAMESPACE"

log "Certificado:"
kubectl get certificate "$TLS_SECRET" -n "$NAMESPACE"

echo
echo "=========================================="
echo " Acesso ao Argo CD configurado!"
echo "=========================================="
echo
echo "URL: https://${HOST}"
echo "Usuário: admin"
echo
echo "Para obter a senha inicial:"
echo "kubectl get secret argocd-initial-admin-secret -n ${NAMESPACE} -o go-template='{{.data.password | base64decode}}'; echo"

