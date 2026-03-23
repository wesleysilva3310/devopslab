#!/bin/bash
set -e

ROLE=$1
NODE_IP=$2

echo "Starting bootstrap for $ROLE ($NODE_IP)"

############################
# WAIT FOR CLOUD INIT
############################
echo "Waiting for cloud-init..."
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
  sleep 2
done

############################
# SSH CONFIG
############################
echo "[COMMON] Configuring SSH"

echo "vagrant:vagrant" | chpasswd

SSH_CLOUDIMG="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"
SSH_OVERRIDE="/etc/ssh/sshd_config.d/99-vagrant-password.conf"

if [ -f "$SSH_CLOUDIMG" ]; then
  sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_CLOUDIMG"
else
  tee "$SSH_OVERRIDE" >/dev/null <<EOF
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
EOF
fi

systemctl reload sshd

############################
# SYSTEM UPDATE
############################
echo "[COMMON] Updating system"
apt update -y && apt upgrade -y

############################
# DNS SERVER SETUP
############################
setup_dns() {
  echo "[DNS] Configuring dnsmasq"

  systemctl disable --now systemd-resolved

  rm -f /etc/resolv.conf
  echo "nameserver 8.8.8.8" > /etc/resolv.conf

  apt update -y
  apt install -y dnsmasq

  cat <<EOF > /etc/dnsmasq.d/k8s.conf
address=/k8smaster/192.168.56.11
address=/k8sworker1/192.168.56.12
address=/k8sworker2/192.168.56.13

server=8.8.8.8

listen-address=0.0.0.0
bind-interfaces
EOF

  systemctl restart dnsmasq
  systemctl enable dnsmasq

  echo "[DNS] Configuration complete"
}

############################
# COMMON K8S SETUP
############################
setup_k8s_common() {

  echo "[K8S] Installing dependencies"
  apt-get install -y apt-transport-https ca-certificates curl gpg

  echo "[K8S] Disable swap"
  swapoff -a
  sed -i '/swap/d' /etc/fstab

  echo "[K8S] Disable firewall"
  systemctl disable --now ufw >/dev/null 2>&1 || true

  echo "[K8S] Kernel modules"
  cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

  modprobe overlay
  modprobe br_netfilter

  cat <<EOF | tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF

  sysctl --system >/dev/null 2>&1

  echo "[K8S] Install containerd"
  apt install -y containerd
  mkdir -p /etc/containerd
  mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# 🔥 FIX: enable systemd cgroup driver
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

  echo "[K8S] Install Kubernetes"
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
  | tee /etc/apt/sources.list.d/kubernetes.list

  apt update -y
  apt install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl
  systemctl enable kubelet
}

############################
# MASTER SETUP
############################
setup_master() {

  echo "[MASTER] Pull images"
  kubeadm config images pull

  echo "[MASTER] Init cluster"
  kubeadm init \
    --apiserver-advertise-address=$NODE_IP \
    --pod-network-cidr=192.168.0.0/16 \
    >> /root/kubeinit.log 2>&1 || true

  echo "[MASTER] Configure kubectl"
  mkdir -p /home/vagrant/.kube
  cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
  chown vagrant:vagrant /home/vagrant/.kube/config

  echo "[MASTER] Install Calico"
  until kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes >/dev/null 2>&1; do
    sleep 5
  done

  kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://docs.projectcalico.org/manifests/calico.yaml

  echo "[MASTER] Waiting before generating join command..."
  sleep 10

  echo "[MASTER] Generate join command"
  kubeadm token create --print-join-command > /vagrant/joincluster.sh
  chmod +x /vagrant/joincluster.sh
}

############################
# WORKER SETUP
############################
setup_worker() {

  MASTER_IP="192.168.56.11"

  echo "[WORKER] Waiting for join command..."
  while [ ! -f /vagrant/joincluster.sh ]; do
    sleep 5
  done

  echo "[WORKER] Waiting for API server..."
  until nc -z $MASTER_IP 6443; do
    sleep 5
  done

  echo "[WORKER] Joining cluster..."

  until bash /vagrant/joincluster.sh; do
    echo "[WORKER] Join failed, resetting and retrying..."

    kubeadm reset -f >/dev/null 2>&1 || true
    rm -rf /etc/kubernetes/*
    rm -rf /var/lib/kubelet/*
    rm -rf /var/lib/etcd

    systemctl restart containerd
    systemctl restart kubelet

    sleep 10
  done

  echo "[WORKER] Successfully joined cluster"
}

############################
# EXECUTION FLOW
############################

if [ "$ROLE" = "dns" ]; then
  setup_dns
fi

if [ "$ROLE" = "master" ] || [ "$ROLE" = "worker" ]; then
  setup_k8s_common
fi

case $ROLE in
  master)
    setup_master
    ;;
  worker)
    setup_worker
    ;;
esac

echo "Bootstrap completed for $ROLE"