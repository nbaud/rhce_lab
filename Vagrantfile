# -*- mode: ruby -*-
# vi: set ft=ruby :

nodes = {
  "control" => { ip: "192.168.56.10", memory: 4096, cpus: 2 },
  "node1"   => { ip: "192.168.56.11", memory: 2048, cpus: 1, research_disk: "2GB", partition_disk: "2GB" },
  "node2"   => { ip: "192.168.56.12", memory: 2048, cpus: 1, research_disk: "2GB" },
  "node3"   => { ip: "192.168.56.13", memory: 2048, cpus: 1, research_disk: "1GB", partition_disk: "1GB" },
  "node4"   => { ip: "192.168.56.14", memory: 2048, cpus: 1, research_disk: "1GB" },
  "node5"   => { ip: "192.168.56.15", memory: 2048, cpus: 1 },
  "repo"    => { ip: "192.168.56.20", memory: 2048, cpus: 1 }
}

hosts_entries = nodes.map do |name, settings|
  "#{settings[:ip]} #{name}.rhce.test #{name}"
end.join("\n")

Vagrant.configure("2") do |config|
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

        # Boot repo from its installed OS, not the attached DVD.
        if name == "repo"
          vb.customize [
            "modifyvm", :id,
            "--boot1", "disk",
            "--boot2", "none",
            "--boot3", "none",
            "--boot4", "none"
          ]
        end
      end

      # Fix host-only routing before any package installation.
      vm.vm.provision "shell",
        name: "network-baseline",
        run: "always",
        privileged: true,
        path: "provision-network.sh"

      # Repository infrastructure: DVD attachment and HTTP service.
      if name == "repo"
        vm.vm.disk :dvd,
          name: "rocky-repository-dvd",
          file: File.expand_path("~/iso/Rocky-10.2-x86_64-dvd1.iso")

        vm.vm.provision "shell",
          name: "repository-server",
          privileged: true,
          path: "provision-repo.sh"
      end

      # Additional research disk; the OS disk is not resized.
      if settings[:research_disk]
        vm.vm.disk :disk,
          name: "rhce-rocky10-#{name}-research",
          size: settings[:research_disk]
      end

      # Separate blank disk for partition exercises.
      if settings[:partition_disk]
        vm.vm.disk :disk,
          name: "rhce-rocky10-#{name}-partition",
          size: settings[:partition_disk]
      end

      vm.vm.provision "shell", privileged: true, inline: <<-SHELL
        set -eu
        dnf -y install openssh-server python3 sudo
        systemctl enable --now sshd

        # Provide consistent name resolution.
        sed -i '/# BEGIN RHCE LAB/,/# END RHCE LAB/d' /etc/hosts
        cat >> /etc/hosts <<'HOSTS'
# BEGIN RHCE LAB
#{hosts_entries}
# END RHCE LAB
HOSTS
      SHELL

      # Install storage tools only on managed practice nodes.
      unless ["control", "repo"].include?(name)
        vm.vm.provision "shell", name: "lvm-tools",
          privileged: true, inline: <<-'SHELL'
          set -eu
          dnf -y install lvm2 e2fsprogs parted
        SHELL
      end

      if settings[:research_disk]
        # Expected layout:
        # /dev/sda = operating system
        # /dev/sdb = research disk
        # /dev/sdc = optional partition exercise disk (left blank)
        vm.vm.provision "shell", name: "research-vg",
          privileged: true,
          args: [settings[:research_disk]], inline: <<-'SHELL'
          set -eu
          udevadm settle

          lab_disk=/dev/sdb
          lab_disk_profile=$1

          fail() {
            echo "RHCE LVM preparation: $*" >&2
            exit 1
          }

          [ -b "$lab_disk" ] ||
            fail "Expected extra disk $lab_disk is missing."

          [ "$(lsblk -dnro TYPE "$lab_disk")" = disk ] ||
            fail "Not a whole disk."

          lab_disk_bytes=$(blockdev --getsize64 "$lab_disk")

          case "$lab_disk_profile" in
            1GB)
              [ "$lab_disk_bytes" -gt 838860800 ] &&
              [ "$lab_disk_bytes" -lt 1258291200 ] ||
                fail "Unexpected size for 1GB lab disk."
              ;;
            2GB)
              [ "$lab_disk_bytes" -gt 1677721600 ] &&
              [ "$lab_disk_bytes" -lt 2516582400 ] ||
                fail "Unexpected size for 2GB lab disk."
              ;;
            *)
              fail "Unknown disk profile: $lab_disk_profile"
              ;;
          esac

          # Preserve existing student work.
          if pvs "$lab_disk" >/dev/null 2>&1; then
            lab_vg=$(pvs --noheadings -o vg_name "$lab_disk" | xargs)

            case "$lab_vg" in
              research)
                echo "research already exists on $lab_disk; preserving student work."
                exit 0
                ;;
              "")
                # Resume after an earlier run stopped after pvcreate.
                ;;
              *)
                fail "$lab_disk belongs to unexpected VG $lab_vg."
                ;;
            esac
          else
            # Require a blank, unused disk.
            [ "$(lsblk -nrpo NAME "$lab_disk" | wc -l)" -eq 1 ] ||
              fail "$lab_disk has partitions or other children."

            [ -z "$(lsblk -nrpo MOUNTPOINTS "$lab_disk" | tr -d '[:space:]')" ] ||
              fail "$lab_disk is mounted or used as swap."

            [ -z "$(wipefs --noheadings --output TYPE "$lab_disk")" ] ||
              fail "$lab_disk already contains a filesystem or disk signature."

            if vgs research >/dev/null 2>&1; then
              fail "research exists on another device; inspect the layout."
            fi

            pvcreate "$lab_disk"
          fi

          if vgs research >/dev/null 2>&1; then
            fail "research already exists elsewhere; refusing to extend it."
          fi

          vgcreate research "$lab_disk"
          echo "Prepared research on $lab_disk. LV creation/formatting is the student's task."
        SHELL
      end
    end
  end
end