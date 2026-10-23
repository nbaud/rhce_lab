# -*- mode: ruby -*-
# vi: set ft=ruby :

nodes = {
  "control" => { ip: "192.168.56.10", memory: 4096, cpus: 2 },
  "node1"   => { ip: "192.168.56.11", memory: 2048, cpus: 1, research_disk: "2GB" },
  "node2"   => { ip: "192.168.56.12", memory: 2048, cpus: 1, research_disk: "2GB" },
  "node3"   => { ip: "192.168.56.13", memory: 2048, cpus: 1, research_disk: "1GB" },
  "node4"   => { ip: "192.168.56.14", memory: 2048, cpus: 1, research_disk: "1GB" },
  "node5"   => { ip: "192.168.56.15", memory: 2048, cpus: 1 }
}

hosts_entries = nodes.map do |name, settings|
  "#{settings[:ip]} #{name}.rhce.test #{name}"
end.join("\n")

Vagrant.configure("2") do |config|
  # This is your existing locally installed box/version.
  # Students must import the same box or select an available box version.
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

      # Vagrant manages creation, attachment and lifecycle of these extra disks.
      # No primary: true: the existing operating-system disk is not resized.
      if settings[:research_disk]
        vm.vm.disk :disk,
          name: "rhce-rocky10-#{name}-research",
          size: settings[:research_disk]
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

      unless name == "control"
        vm.vm.provision "shell", name: "lvm-tools", privileged: true, inline: <<-'SHELL'
          set -eu
          dnf -y install lvm2 e2fsprogs
        SHELL
      end

      if settings[:research_disk]
        # This box has its OS on /dev/sda; the only extra disk is /dev/sdb.
        # Refuse unexpected layouts rather than selecting another disk.
        vm.vm.provision "shell", name: "research-vg", privileged: true,
          args: [settings[:research_disk]], inline: <<-'SHELL'
          set -eu
          udevadm settle
          lab_disk=/dev/sdb
          lab_disk_profile=$1

          fail() { echo "RHCE LVM preparation: $*" >&2; exit 1; }
          [ -b "$lab_disk" ] || fail "Expected extra disk $lab_disk is missing."
          [ "$(lsblk -dnro TYPE "$lab_disk")" = disk ] || fail "Not a whole disk."
          lab_disk_bytes=$(blockdev --getsize64 "$lab_disk")
          case "$lab_disk_profile" in
            1GB)
              [ "$lab_disk_bytes" -gt 838860800 ] &&
              [ "$lab_disk_bytes" -lt 1258291200 ] || fail "Unexpected size for 1GB lab disk."
              ;;
            2GB)
              [ "$lab_disk_bytes" -gt 1677721600 ] &&
              [ "$lab_disk_bytes" -lt 2516582400 ] || fail "Unexpected size for 2GB lab disk."
              ;;
            *) fail "Unknown disk profile: $lab_disk_profile" ;;
          esac

          # Existing research PV/VG: preserve students' data LVs and filesystems.
          if pvs "$lab_disk" >/dev/null 2>&1; then
            lab_vg=$(pvs --noheadings -o vg_name "$lab_disk" | xargs)
            case "$lab_vg" in
              research)
                echo "research already exists on $lab_disk; preserving student work."
                exit 0
                ;;
              "") ;; # Resume if an earlier provisioning run stopped after pvcreate.
              *) fail "$lab_disk belongs to unexpected VG $lab_vg." ;;
            esac
          else
            # A blank disk has one lsblk row, no signatures and no mounts/swap.
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
      # node5 deliberately has no extra disk and no research VG.
    end
  end
end
