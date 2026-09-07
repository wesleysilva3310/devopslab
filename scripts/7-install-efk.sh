#!/bin/bash

set -e

echo "🚀 Starting EFK stack installation with NFS persistence..."

NAMESPACE="logging"
STORAGE_CLASS="nfs-client"   # 👈 CHANGE if your SC name is different

# -----------------------------
# CREATE NAMESPACE
# -----------------------------
echo "📁 Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# -----------------------------
# ADD HELM REPOS
# -----------------------------
echo "📦 Adding Helm repos..."
helm repo add elastic https://helm.elastic.co >/dev/null 2>&1
helm repo add fluent https://fluent.github.io/helm-charts >/dev/null 2>&1
helm repo update >/dev/null

# -----------------------------
# INSTALL ELASTICSEARCH (WITH NFS)
# -----------------------------
echo "🔍 Installing Elasticsearch with NFS persistence..."

helm upgrade --install elasticsearch elastic/elasticsearch \
  --namespace $NAMESPACE \
  --set replicas=1 \
  --set minimumMasterNodes=1 \
  --set resources.requests.cpu="100m" \
  --set resources.requests.memory="512Mi" \
  --set resources.limits.memory="1Gi" \
  --set persistence.enabled=true \
  --set volumeClaimTemplate.resources.requests.storage="10Gi" \
  --set volumeClaimTemplate.storageClassName="$STORAGE_CLASS" \
  --set discovery.type=single-node

# -----------------------------
# WAIT FOR ELASTICSEARCH
# -----------------------------
echo "⏳ Waiting for Elasticsearch..."
kubectl rollout status statefulset/elasticsearch-master -n $NAMESPACE

# -----------------------------
# VERIFY PVC (IMPORTANT)
# -----------------------------
echo "🔎 Checking PVC..."
kubectl get pvc -n $NAMESPACE

# -----------------------------
# GET ELASTIC PASSWORD
# -----------------------------
echo "🔐 Fetching Elasticsearch password..."

ES_PASS=$(kubectl get secret elasticsearch-master-credentials \
  -n $NAMESPACE \
  -o jsonpath="{.data.password}" | base64 -d)

echo "✅ Password fetched"

# -----------------------------
# INSTALL KIBANA
# -----------------------------
echo "📊 Installing Kibana..."

helm upgrade --install kibana elastic/kibana \
  --namespace $NAMESPACE \
  --set service.type=NodePort \
  --set resources.requests.cpu="100m" \
  --set resources.requests.memory="256Mi" \
  --set resources.limits.memory="512Mi"

# -----------------------------
# CREATE FLUENT BIT VALUES (DYNAMIC)
# -----------------------------
echo "🪵 Creating Fluent Bit config..."

cat <<EOF > fluent-bit-values.yaml
config:
  service: |
    [SERVICE]
        Flush        1
        Log_Level    info
        Daemon       Off
        HTTP_Server  On
        HTTP_Listen  0.0.0.0
        HTTP_Port    2020

  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        Parser            docker
        Tag               kube.*
        Refresh_Interval  5
        Mem_Buf_Limit     5MB
        Skip_Long_Lines   On

  filters: |
    [FILTER]
        Name                kubernetes
        Match               kube.*
        Merge_Log           On
        Keep_Log            Off
        K8S-Logging.Parser  On
        K8S-Logging.Exclude On

  outputs: |
    [OUTPUT]
        Name                es
        Match               kube.*
        Host                elasticsearch-master.logging.svc.cluster.local
        Port                9200
        HTTP_User           elastic
        HTTP_Passwd         ${ES_PASS}
        tls                 On
        tls.verify          Off
        Logstash_Format     On
        Logstash_Prefix     kube
        Suppress_Type_Name  On
        Retry_Limit         False
EOF

# -----------------------------
# INSTALL FLUENT BIT
# -----------------------------
echo "🚀 Installing Fluent Bit..."

helm upgrade --install fluent-bit fluent/fluent-bit \
  -n $NAMESPACE \
  -f fluent-bit-values.yaml

# -----------------------------
# FINAL STATUS
# -----------------------------
echo "📦 Pods status:"
kubectl get pods -n $NAMESPACE

echo "💾 PVC status:"
kubectl get pvc -n $NAMESPACE

echo "🔑 Elasticsearch password: $ES_PASS"

echo "✅ EFK stack with NFS persistence deployed successfully!"
