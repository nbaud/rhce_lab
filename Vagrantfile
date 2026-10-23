# -*- mode: ruby -*-
# vi: set ft=ruby :

nodes = {
  "control" => { ip: "192.168.56.10", memory: 4096, cpus: 2 },
  "node1"   => { ip: "192.168.56.11", memory: 2048, cpus: 1 },
  "node2"   => { ip: "192.168.56.12", memory: 2048, cpus: 1 },
  "node3"   => { ip: "192.168.56.13", memory: 2048, cpus: 1 },
  "node4"   => { ip: "192.168.56.14", memory: 2048, cpus: 1 },
  "node5"   => { ip: "192.168.56.15", memory: 2048, cpus: 1 }
}

hosts_entries = nodes.map do |name, settings|
  "#{settings[:ip]} #{name}.rhce.test #{name}"
end.join("\n")

Vagrant.configure("2") do |config|
  # Use the Rocky 10 VirtualBox image already installed on nexus.
  config.vm.box = "rockylinux/10"
  config.vm.box_version = "0"
  config.vm.box_check_update = false

  config.vm.synced_folder ".", "/vagrant", disabled: true

  nodes.each do |name, settings|
    config.vm.define name do |vm|
      vm.vm.hostname = "#{name}.rhce.test"

      vm.vm.network "private_network",
        ip: settings[:ip],
        netmask: "255.255.255.0",
        virtualbox__hostonly: "vboxnet0"

      vm.vm.provider "virtualbox" do |vb|
        vb.name = "rhce-rocky10-#{name}"
        vb.memory = settings[:memory]
        vb.cpus = settings[:cpus]
        vb.gui = false
      end

      vm.vm.provision "shell", privileged: true, inline: <<-SHELL
        set -eu

        dnf -y install openssh-server python3 sudo
        systemctl enable --now sshd

        # Provide consistent name resolution on every lab machine.
        sed -i '/# BEGIN RHCE LAB/,/# END RHCE LAB/d' /etc/hosts
        cat >> /etc/hosts <<'HOSTS'
# BEGIN RHCE LAB
#{hosts_entries}
# END RHCE LAB
HOSTS
      SHELL
    end
  end
end
