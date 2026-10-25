#!/usr/bin/env bash
set -euo pipefail

dnf -y install httpd firewalld

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

# Fail provisioning if the expected repositories aren't available.
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

if [ -z "$lab_interface" ]; then
    echo "Cannot find the interface with 192.168.56.20/24" >&2
    exit 1
fi

lab_zone=$(firewall-cmd --get-zone-of-interface="$lab_interface" || true)

if [ -z "$lab_zone" ] || [ "$lab_zone" = "no zone" ]; then
    lab_zone=$(firewall-cmd --get-default-zone)
fi

firewall-cmd --zone="$lab_zone" --permanent --add-service=http
firewall-cmd --zone="$lab_zone" --add-service=http

httpd -t
systemctl enable --now httpd

curl --fail --silent --output /dev/null \
    http://127.0.0.1/rocky/BaseOS/repodata/repomd.xml

curl --fail --silent --output /dev/null \
    http://127.0.0.1/rocky/AppStream/repodata/repomd.xml

echo "Repository server ready: http://192.168.56.20/rocky/"
