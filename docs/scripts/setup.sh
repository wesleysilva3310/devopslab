#!/bin/bash
set -e

############################
# SSH PASSWORD FIX (UBUNTU CLOUD IMAGES)
############################
echo "Waiting for cloud-init to finish..."
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
  sleep 2
done

echo "Configuring SSH password authentication"

# Ensure vagrant user has a password
echo "vagrant:vagrant" | sudo chpasswd

SSH_CLOUDIMG="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"
SSH_OVERRIDE="/etc/ssh/sshd_config.d/99-vagrant-password.conf"

# If Ubuntu cloud image policy exists, patch it
if [ -f "$SSH_CLOUDIMG" ]; then
  sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_CLOUDIMG"
else
  # Fallback override (for non-cloud images)
  sudo tee "$SSH_OVERRIDE" >/dev/null <<EOF
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
EOF
fi

sudo systemctl reload sshd

echo "Effective SSH setting:"
sudo sshd -T | grep passwordauthentication

# Updating linux
echo "Updating Linux"
sudo apt update -y && sudo apt upgrade -y
echo "LINUX UPDATED."

# Install sshpass
echo "Installing sshpass"
sudo apt-get install sshpass -y
echo "INSTALLATION COMPLETE!"

# Install docker in other vms outside k8s cluster specified on vagrantfile
if
        [ "$HOSTNAME" != k8smaster ] && [ "$HOSTNAME" != k8sworker1 ] && [ "$HOSTNAME" != k8sworker2 ];
then
echo "Installing docker"
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt install docker docker.io -y
sudo usermod -aG docker vagrant
echo "INSTALLATION COMPLETE!"

# Installing docker-compose
echo "Installing docker compose"
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
sudo curl \
    -L https://raw.githubusercontent.com/docker/compose/1.29.2/contrib/completion/bash/docker-compose \
    -o /etc/bash_completion.d/docker-compose
echo "INSTALLATION COMPLETE!"
fi

# Configuring dns server
if [ "$HOSTNAME" = dnsserver ];
then
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved
sudo unlink /etc/resolv.conf
echo nameserver 8.8.8.8 | sudo tee /etc/resolv.conf
sudo apt install dnsmasq
sudo systemctl restart dnsmasq
sudo cat >>/etc/hosts<<EOF
192.168.1.100   k8smaster
192.168.1.105   dnsserver
192.168.1.101   k8sworker1
192.168.1.102   k8sworker2
192.168.1.132   jenkins
EOF
fi

#Adding dns server to resolv.conf
sudo cat >>/etc/resolv.conf<<EOF
nameserver 192.168.1.105
EOF

# Installing ansible on k8smaster vm
if
        [ "$HOSTNAME" = k8smaster ];
then
        echo "Installing ansible on k8smaster VM"
        sudo apt install ansible -y
        echo "INSTALLATION COMPLETE!"
fi

# installing helm on k8smaster vm
if
        [ "$HOSTNAME" = k8smaster ];
then
        echo "Installing helm on k8smaster VM"
        wget https://get.helm.sh/helm-v3.9.0-linux-amd64.tar.gz
        tar -zxvf helm-v3.9.0-linux-amd64.tar.gz
        mv linux-amd64/helm /usr/local/bin/helm
        rm -Rf helm-v3.9.0-linux-amd64.tar.gz linux-amd64
        echo "INSTALLATION COMPLETE!"
fi

#Kubernetes configuration

if 
        [ "$HOSTNAME" = k8smaster ] || [ "$HOSTNAME" = k8sworker1 ] || [ "$HOSTNAME" = k8sworker2 ];
then

echo "[k8s TASK 0] install dependencies"
apt-get install -y apt-transport-https ca-certificates curl gpg

echo "[k8s TASK 1] Disable and turn off SWAP"
sed -i '/swap/d' /etc/fstab
swapoff -a

echo "[k8s TASK 2] Stop and Disable firewall"
systemctl disable --now ufw >/dev/null 2>&1

echo "[k8s TASK 3] Enable and Load Kernel modules"
cat >>/etc/modules-load.d/containerd.conf<<END1
overlay
br_netfilter
END1
modprobe overlay
modprobe br_netfilter

echo "[k8s TASK 4] Add Kernel settings"
cat >>/etc/sysctl.d/kubernetes.conf<<END2
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
END2
sysctl --system >/dev/null 2>&1

echo "[k8s TASK 5] Install containerd runtime"
apt update -qq >/dev/null 2>&1
apt install -qq -y containerd apt-transport-https >/dev/null 2>&1
mkdir /etc/containerd
containerd config default > /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd >/dev/null 2>&1

echo "[k8s TASK 6] Add apt repo for kubernetes"
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

echo "[k8s TASK 7] Install Kubernetes components (kubeadm, kubelet and kubectl)"
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

echo "[k8s TASK 8] Enable ssh password authentication"
sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
systemctl reload sshd

echo "[k8s TASK 9] Set root password"
echo -e "kubeadmin\nkubeadmin" | passwd root >/dev/null 2>&1
echo "export TERM=xterm" >> /etc/bash.bashrc

echo "[k8s TASK 10] Update /etc/hosts file"
cat >>/etc/hosts<<END3
192.168.1.100  k8smaster
192.168.1.101  k8sworker1
192.168.1.102  k8sworker2
END3

echo "K8s bootstrap configuration complete!"
fi
#Creating script to add kube dir and permissions
if
        [ "$HOSTNAME" = k8smaster ];
then
echo "[k8s k8smaster TASK 1] Pull required containers"
kubeadm config images pull >/dev/null 2>&1

echo "[k8s k8smaster TASK 2] Initialize Kubernetes Cluster"
kubeadm init \
  --apiserver-advertise-address=192.168.1.100 \
  --pod-network-cidr=192.168.0.0/16 \
  >> /root/kubeinit.log 2>&1 || true


echo "[k8s k8smaster TASK 3] Deploy Calico network"
echo "Waiting for API server..."
until kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes >/dev/null 2>&1; do
  sleep 5
done

kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://docs.projectcalico.org/v3.18/manifests/calico.yaml || true

echo "[k8s k8smaster TASK 4] Generate and save cluster join command to /joincluster.sh"
kubeadm token create --print-join-command > /joincluster.sh 2>/dev/null
sleep 30

#

cat > kubemastersetup.sh << END4
#run as vagrant user
echo "Creating kube dir and permissions"
 mkdir -p /home/vagrant/.kube
 sudo cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
 sudo chown $(id -u):$(id -g) /home/vagrant/.kube/config
echo "k8s k8smaster configuration complete!"
END4
fi

#Creating script to k8s workers to be added to cluster
if 
        [ "$HOSTNAME" = k8sworker1 ] || [ "$HOSTNAME" = k8sworker2 ];
then
#run this only when creating the VM for the first time, using root user
cat > /usr/joincluster.sh << EOF
echo "Join node to Kubernetes Cluster"
apt install -qq -y sshpass >/dev/null 2>&1
sshpass -p "kubeadmin" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no k8smaster:/joincluster.sh /joincluster.sh 2>/dev/null
bash /joincluster.sh >/dev/null 2>&1
EOF
fi

# Install docker on k8s nodes
if
        [ "$HOSTNAME" = k8smaster ];
then
echo "Installing docker"
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt install docker docker.io -y
sudo usermod -aG docker vagrant
echo "Installation Complete!"

# Installing docker-compose
echo "Installing docker compose"
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
sudo curl \
    -L https://raw.githubusercontent.com/docker/compose/1.29.2/contrib/completion/bash/docker-compose \
    -o /etc/bash_completion.d/docker-compose
echo "Installation Complete!"
fi

# Installing gitlab on gitlab server
if
        [ "$HOSTNAME" = gitlab ];
then
echo "Installing gitlab on $HOSTNAME"
mkdir /home/vagrant/gitlab
export GITLAB_HOME=/srv/gitlab
export GITLAB_HOME=/home/vagrant/gitlab
cd $GITLAB_HOME

cat > docker-compose.yml << EOF
version: '3.5'
services:
 gitlab:
  image: 'gitlab/gitlab-ee:latest'
  restart: always
  hostname: 'dockerenv-gitlab.wesleylab.com'
  environment:
    GITLAB_OMNIBUS_CONFIG: |
      external_url 'http://dockerenv-gitlab.wesleylab.com'
      # Add any other gitlab.rb configuration here, each on its own line
  ports:
    - '80:80'
    - '443:443'
    - '2224:2224'
  volumes:
    - '$GITLAB_HOME/config:/etc/gitlab'
    - '$GITLAB_HOME/logs:/var/log/gitlab'
    - '$GITLAB_HOME/data:/var/opt/gitlab'
EOF
cd gitlab && docker-compose up -d
# Initial password: docker exec -it gitlab_gitlab_1 cat /etc/gitlab/initial_root_password
echo "Installation complete!"
fi

# Install Jenkins
if
        [ "$HOSTNAME" = jenkins ];
then

mkdir jenkins && cd jenkins
cat > docker-compose.yml << EOF
version: "3.9"
services:
  jenkins:
    image: jenkins/jenkins:lts
    container_name: jenkins-server
    privileged: true
    hostname: jenkinsserver
    user: root
    labels:
      com.example.description: "Jenkins-Server by DigitalAvenue.dev"
    ports: 
      - "8080:8080"
      - "50000:50000"
    networks:
      jenkins-net:
        aliases: 
          - jenkins-net
    volumes: 
     - jenkins-data:/var/jenkins_home
     - /var/run/docker.sock:/var/run/docker.sock
     
volumes: 
  jenkins-data:
networks:
  jenkins-net:
EOF
fi