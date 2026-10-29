# -*- mode: ruby -*-
# vi: set ft=ruby :

require "open3"
require "vagrant/action/builtin/disk"
require "vagrant/action/builtin/cleanup_disks"

# Workaround for Vagrant 2.4.9 + VirtualBox snapshots.
#
# Without snapshots: normal Vagrant disk management.
# With snapshots: skip BOTH disk configuration and disk cleanup.
# Existing attachments and disk_meta remain untouched.
module RhceSnapshotStorageGuard
  def call(env)
    machine = env[:machine]

    if machine.provider_name.to_s == "virtualbox" && machine.id
      output, error, status = Open3.capture3(
        "VBoxManage",
        "showvminfo",
        machine.id,
        "--machinereadable"
      )

      unless status.success?
        raise "Cannot inspect #{machine.name} before disk management: #{error.strip}"
      end

      if output.match?(/^CurrentSnapshotUUID="[^"]+"/)
        step =
          if is_a?(Vagrant::Action::Builtin::CleanupDisks)
            "disk cleanup"
          else
            "disk configuration"
          end

        env[:ui].info(
          "Snapshot detected: skipping #{step}; preserving existing storage."
        )

        return @app.call(env)
      end
    end

    super
  end
end

[
  Vagrant::Action::Builtin::CleanupDisks,
  Vagrant::Action::Builtin::Disk
].each do |middleware|
  unless middleware.ancestors.include?(RhceSnapshotStorageGuard)
    middleware.prepend(RhceSnapshotStorageGuard)
  end
end

nodes = {
  "control" => {
    ip: "192.168.56.10", memory: 4096, cpus: 2
  },
  "node1" => {
    ip: "192.168.56.11", memory: 2048, cpus: 1,
    research_disk: "2GB", partition_disk: "2GB"
  },
  "node2" => {
    ip: "192.168.56.12", memory: 2048, cpus: 1,
    research_disk: "2GB"
  },
  "node3" => {
    ip: "192.168.56.13", memory: 2048, cpus: 1,
    research_disk: "1GB", partition_disk: "1GB"
  },
  "node4" => {
    ip: "192.168.56.14", memory: 2048, cpus: 1,
    research_disk: "1GB"
  },
  "node5" => {
    ip: "192.168.56.15", memory: 2048, cpus: 1
  },
  "repo" => {
    ip: "192.168.56.20", memory: 2048, cpus: 1
  }
}

hosts_entries = nodes.map do |name, settings|
  "#{settings[:ip]} #{name}.rhce.test #{name}"
end.join("\n")

Vagrant.configure("2") do |config|
if Vagrant.has_plugin?("vagrant-vbguest")
  config.vbguest.auto_update = false
end
  config.vm.box = "rockylinux/10"
  config.vm.box_check_update = false
  config.vm.box_url = "https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-Vagrant-Vbox-10.2-20260525.0.x86_64.vagrant.virtualbox.box"
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
        vb.memory = (name == "control" ? 2048 : 1024)
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

      # Always retain storage declarations.
      # The middleware guard skips storage operations when snapshots exist.
      if name == "repo"
        vm.vm.disk :dvd,
          name: "rocky-repository-dvd",
          file: File.expand_path("~/iso/Rocky-10.2-x86_64-dvd1.iso")
      end

      # Declare research first so it precedes the partition exercise disk.
      if settings[:research_disk]
        vm.vm.disk :disk,
          name: "rhce-rocky10-#{name}-research",
          size: settings[:research_disk]
      end

      if settings[:partition_disk]
        vm.vm.disk :disk,
          name: "rhce-rocky10-#{name}-partition",
          size: settings[:partition_disk]
      end

      # Run on every startup, before any package installation.
      vm.vm.provision "shell",
        name: "network-baseline",
        run: "always",
        privileged: true,
        inline: <<-'SHELL'
          #!/usr/bin/env bash
          set -euo pipefail

          restorecon -RF /etc/NetworkManager/system-connections

          lab_connection=$(nmcli -g GENERAL.CONNECTION device show enp0s8)

          if [[ -z "$lab_connection" || "$lab_connection" == "--" ]]; then
            echo "No active NetworkManager connection found for enp0s8" >&2
            exit 1
          fi

          # NAT supplies the default route, not the host-only interface.
          nmcli connection modify "$lab_connection" \
            ipv4.never-default yes \
            ipv4.gateway "" \
            ipv6.never-default yes

          nmcli device reapply enp0s8

          echo "Network preparation complete:"
          ip -4 route
        SHELL

      vm.vm.provision "shell",
        name: "common-baseline",
        privileged: true,
        inline: <<-SHELL
          #!/usr/bin/env bash
          set -euo pipefail

          dnf -y install openssh-server python3 sudo
          systemctl enable --now sshd

          # Replace only this lab's managed entries.
          sed -i '/# BEGIN RHCE LAB/,/# END RHCE LAB/d' /etc/hosts

          cat >> /etc/hosts <<'HOSTS'
# BEGIN RHCE LAB
#{hosts_entries}
# END RHCE LAB
HOSTS
        SHELL

      if name == "repo"
        vm.vm.provision "shell",
          name: "repository-server",
          privileged: true,
          inline: <<-'SHELL'
            #!/usr/bin/env bash
            set -euo pipefail

            dnf -y install httpd firewalld curl

            repo_mount=/var/www/html/rocky
            mkdir -p "$repo_mount"

            # Replace our mount entry rather than appending duplicates.
            sed -i '\|^[^#][^[:space:]]*[[:space:]]\+/var/www/html/rocky[[:space:]]|d' /etc/fstab

            cat >> /etc/fstab <<'FSTAB'
LABEL=Rocky-10-2-x86_64-dvd /var/www/html/rocky iso9660 ro,context=system_u:object_r:httpd_sys_content_t:s0 0 0
FSTAB

            systemctl daemon-reload

            if ! mountpoint -q "$repo_mount"; then
              mount "$repo_mount"
            fi

            test -f "$repo_mount/BaseOS/repodata/repomd.xml"
            test -f "$repo_mount/AppStream/repodata/repomd.xml"

            # Apache must wait for the DVD mount.
            mkdir -p /etc/systemd/system/httpd.service.d

            cat > /etc/systemd/system/httpd.service.d/repository.conf <<'SYSTEMD'
[Unit]
RequiresMountsFor=/var/www/html/rocky
SYSTEMD

            systemctl daemon-reload
            systemctl enable --now firewalld

            # Open HTTP in the zone used by the lab-facing interface.
            lab_interface=$(ip -o -4 addr show |
              awk '$4 == "192.168.56.20/24" {print $2; exit}')

            if [[ -z "$lab_interface" ]]; then
              echo "Cannot find the interface with 192.168.56.20/24" >&2
              exit 1
            fi

            lab_zone=$(firewall-cmd \
              --get-zone-of-interface="$lab_interface" || true)

            if [[ -z "$lab_zone" || "$lab_zone" == "no zone" ]]; then
              lab_zone=$(firewall-cmd --get-default-zone)
            fi

            firewall-cmd --zone="$lab_zone" --permanent --add-service=http
            firewall-cmd --zone="$lab_zone" --add-service=http

            httpd -t
            systemctl enable --now httpd

            curl --fail --silent --show-error --output /dev/null \
              http://127.0.0.1/rocky/BaseOS/repodata/repomd.xml

            curl --fail --silent --show-error --output /dev/null \
              http://127.0.0.1/rocky/AppStream/repodata/repomd.xml

            echo "Repository server ready: http://192.168.56.20/rocky/"
          SHELL
      end

      # Install storage tools only on managed practice nodes.
      unless ["control", "repo"].include?(name)
        vm.vm.provision "shell",
          name: "lvm-tools",
          privileged: true,
          inline: <<-'SHELL'
            #!/usr/bin/env bash
            set -euo pipefail

            dnf -y install lvm2 e2fsprogs parted
          SHELL
      end

      if settings[:research_disk]
        # Expected layout for this box:
        # /dev/sda = operating system
        # /dev/sdb = research disk
        # /dev/sdc = optional partition exercise disk, left blank
        vm.vm.provision "shell",
          name: "research-vg",
          privileged: true,
          args: [settings[:research_disk]],
          inline: <<-'SHELL'
            #!/usr/bin/env bash
            set -euo pipefail

            udevadm settle

            lab_disk=/dev/sdb
            lab_disk_profile=$1

            fail() {
              echo "RHCE LVM preparation: $*" >&2
              exit 1
            }

            [[ -b "$lab_disk" ]] ||
              fail "Expected extra disk $lab_disk is missing."

            [[ "$(lsblk -dnro TYPE "$lab_disk")" == disk ]] ||
              fail "$lab_disk is not a whole disk."

            lab_disk_bytes=$(blockdev --getsize64 "$lab_disk")

            case "$lab_disk_profile" in
              1GB)
                [[ "$lab_disk_bytes" -gt 838860800 &&
                   "$lab_disk_bytes" -lt 1258291200 ]] ||
                  fail "Unexpected size for 1GB lab disk."
                ;;
              2GB)
                [[ "$lab_disk_bytes" -gt 1677721600 &&
                   "$lab_disk_bytes" -lt 2516582400 ]] ||
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
                  # Resume if an earlier run stopped after pvcreate.
                  ;;
                *)
                  fail "$lab_disk belongs to unexpected VG $lab_vg."
                  ;;
              esac
            else
              # Require a blank, unused disk.
              [[ "$(lsblk -nrpo NAME "$lab_disk" | wc -l)" -eq 1 ]] ||
                fail "$lab_disk has partitions or other children."

              [[ -z "$(lsblk -nrpo MOUNTPOINTS "$lab_disk" |
                tr -d '[:space:]')" ]] ||
                fail "$lab_disk is mounted or used as swap."

              [[ -z "$(wipefs --noheadings --output TYPE "$lab_disk")" ]] ||
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

            echo "Prepared research on $lab_disk."
            echo "LV creation and formatting are the student's task."
          SHELL
      end
    end
  end
end
