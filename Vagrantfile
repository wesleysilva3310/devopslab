ENV['VAGRANT_NO_PARALLEL'] = 'yes'

# -----------------------------
# Cluster Node Definitions
# -----------------------------
NODES = [
  { name: "dnsserver",  ip: "192.168.56.10", cpu: 1, ram: 1024, role: "dns" },
  { name: "k8smaster", ip: "192.168.56.11", cpu: 2, ram: 4096, role: "master", disk: "80GB" },
  { name: "k8sworker1", ip: "192.168.56.12", cpu: 2, ram: 2048, role: "worker" },
  { name: "k8sworker2", ip: "192.168.56.13", cpu: 2, ram: 2048, role: "worker" }
]

Vagrant.configure("2") do |config|

  # Base box
  config.vm.box = "ubuntu/jammy64"
  config.vm.box_check_update = false

  # Synced folder
  config.vm.synced_folder ".", "/vagrant"

  NODES.each do |node|
    config.vm.define node[:name] do |machine|

      machine.vm.hostname = node[:name]
      machine.vm.network "private_network", ip: node[:ip]

      # ✅ Disk size (ONLY if defined)
      if node[:disk]
        machine.disksize.size = node[:disk]
      end

      machine.vm.provider :virtualbox do |vb|
        vb.name   = node[:name]
        vb.memory = node[:ram]
        vb.cpus   = node[:cpu]
      end

      machine.vm.provision "shell",
        path: "scripts/bootstrap.sh",
        args: [node[:role], node[:ip]],
        privileged: true

    end
  end
end