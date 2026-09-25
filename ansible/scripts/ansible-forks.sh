#!/bin/sh
# Prints a fork count for Ansible sized to the memory this machine or container can use: 100 MiB
# per fork, with 25% held back for the controller, ssh and the host, and never fewer than
# Ansible's default of 5. A container's --memory limit wins over the host's MemTotal. Used by the
# Makefile and ansible/molecule/common/bastion-run.yml; set ANSIBLE_FORKS to override.
mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
limit="$(cat /sys/fs/cgroup/memory.max 2>/dev/null)"
case "$limit" in
  ''|max) ;;
  *) [ $((limit / 1024)) -lt "$mem_kb" ] && mem_kb=$((limit / 1024)) ;;
esac
forks=$((mem_kb * 75 / 100 / 1024 / 100))
[ "$forks" -ge 5 ] || forks=5
echo "$forks"
