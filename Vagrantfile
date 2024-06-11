ENV['VAGRANT_NO_PARALLEL'] = 'yes'

Vagrant.configure("2") do |config|

  # DNS Server
  config.vm.define "dnsserver" do |dns|
  
    dns.vm.box               = "ubuntu/focal64"
    dns.vm.box_check_update  = false
    dns.vm.hostname          = "dnsserver"

    dns.vm.network "public_network", ip: "192.168.1.105"
    dns.vm.provision "shell", path: "setup.sh"
  end

  # Kubernetes Master Server
  config.vm.define "k8smaster" do |node|
  
    node.vm.box               = "ubuntu/focal64"
    node.vm.box_check_update  = false
    node.vm.hostname          = "k8smaster"

    node.vm.network "public_network", ip: "192.168.1.100"
  
    node.vm.provider :virtualbox do |v|
      v.name    = "k8smaster"
      v.memory  = 4048
      v.cpus    =  2
    end
    node.vm.provision "shell", path: "setup.sh"
  
  end
# Gitlab
config.ssh.insert_key = false

config.vm.define "gitlab" do |gitlab|

  gitlab.vm.box               = "ubuntu/focal64"
  gitlab.vm.hostname          = "gitlab"

  gitlab.vm.network "public_network", ip: "192.168.1.130"
  
  gitlab.vm.provider :virtualbox do |gitlabsetup|
      gitlabsetup.memory = 9000
      gitlabsetup.cpus = 4
      end

  gitlab.vm.network "forwarded_port", guest: 80, host: 80
  gitlab.vm.network "forwarded_port", guest: 443, host: 443
  gitlab.vm.network "forwarded_port", guest: 2224, host: 2224
  gitlab.vm.network "forwarded_port", guest: 5050, host: 5050
  gitlab.vm.provision "shell", path: "setup.sh"
end
  # Kubernetes Worker Nodes
  NodeCount = 2

  (1..NodeCount).each do |i|

    config.vm.define "k8sworker#{i}" do |node|

      node.vm.box               = "ubuntu/focal64"
      node.vm.box_check_update  = false
      node.vm.hostname          = "k8sworker#{i}"

      node.vm.network "public_network", ip: "192.168.1.10#{i}"

      node.vm.provider :virtualbox do |v|
        v.name    = "k8sworker#{i}"
        v.memory  = 4024
        v.cpus    = 1
      end
      node.vm.provision "shell", path: "setup.sh"
    end
  end
end