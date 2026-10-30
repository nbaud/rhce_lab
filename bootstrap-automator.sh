#!/bin/bash
set -euo pipefail

ssh-keygen -lf /tmp/bootstrap_automator.pub >/dev/null
id automator >/dev/null 2>&1 || useradd -m -s /bin/bash automator

install -d -m 0700 -o automator -g automator /home/automator/.ssh
auth=/home/automator/.ssh/authorized_keys
touch "$auth"
key=$(cat /tmp/bootstrap_automator.pub)
grep -qxF "$key" "$auth" || printf '%s\n' "$key" >> "$auth"
chown automator:automator "$auth"
chmod 0600 "$auth"
restorecon -RF /home/automator/.ssh

candidate=$(mktemp)
trap 'rm -f "$candidate"' EXIT
printf '%s\n' 'automator ALL=(ALL) NOPASSWD: ALL' > "$candidate"
visudo -cf "$candidate"
install -m 0440 -o root -g root "$candidate" /etc/sudoers.d/automator
restorecon /etc/sudoers.d/automator
