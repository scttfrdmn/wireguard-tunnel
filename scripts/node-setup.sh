#!/usr/bin/env bash
# node-setup.sh — one-time per-node prep. Run with sudo on BOTH nodes.
set -euo pipefail
source "$(dirname "$0")/common.sh"

[ "$(id -u)" -eq 0 ] || die "run as root (sudo)"

log "installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# NB: no awscli here — Ubuntu 24.04 has no 'awscli' apt package, and the nodes don't need it
# (ENA Express is toggled from the operator host via enable-ena-express.sh).
apt-get install -y -qq wireguard-tools iperf3 fio ethtool sysstat jq \
  linux-tools-common "linux-tools-$(uname -r)" build-essential nvme-cli \
  numactl irqbalance >/dev/null

# nvme-tcp (initiator) and nvmet-tcp (target) live in linux-modules-extra on the AWS kernel,
# not the base image — needed for the NVMe->NVMe over nvme-tcp test (measure-nvme-tcp.sh).
log "ensuring nvme-tcp / nvmet-tcp kernel modules"
apt-get install -y -qq "linux-modules-extra-$(uname -r)" >/dev/null 2>&1 || true
modprobe nvme-tcp  2>/dev/null || log "WARN: nvme-tcp module unavailable (nvme-tcp test will not run)"
modprobe nvmet-tcp 2>/dev/null || log "WARN: nvmet-tcp module unavailable (nvme-tcp target will not run)"

log "kernel: $(uname -r)  — in-tree wireguard present: $(modinfo wireguard >/dev/null 2>&1 && echo yes || echo NO)"
modinfo wireguard >/dev/null 2>&1 || die "kernel wireguard module missing; need 5.6+ (6.x recommended)"

log "jumbo MTU on $PRIMARY_IF -> 9001"
ip link set dev "$PRIMARY_IF" mtu 9001

log "max out ENA combined queues"
MAXQ=$(ethtool -l "$PRIMARY_IF" | awk '/Combined/{print $2; exit}')
ethtool -L "$PRIMARY_IF" combined "$MAXQ" || true
log "ENA combined queues = $MAXQ"

log "sysctls for high-rate forwarding + ECMP L4 hashing"
cat >/etc/sysctl.d/99-wg-saturate.conf <<EOF
net.ipv4.fib_multipath_hash_policy = 1
net.core.rmem_max = 536870912
net.core.wmem_max = 536870912
net.core.netdev_max_backlog = 250000
net.ipv4.tcp_rmem = 4096 262144 268435456
net.ipv4.tcp_wmem = 4096 262144 268435456
net.ipv4.ip_forward = 1
EOF
sysctl -p /etc/sysctl.d/99-wg-saturate.conf >/dev/null

log "performance governor + shallow C-states (best effort)"
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$g" 2>/dev/null || true; done

log "hugepages (8 GiB of 2M pages for mover buffers)"
echo 4096 > /proc/sys/vm/nr_hugepages 2>/dev/null || true

# IRQ pinning: stop irqbalance, pin ENA queue IRQs across cores round-robin.
log "pinning ENA IRQs (irqbalance off)"
systemctl stop irqbalance 2>/dev/null || true
NCORES=$(nproc)
i=0
while read -r irq; do
  cpu=$(( i % NCORES ))
  echo "$cpu" > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null || true
  i=$((i+1))
done < <(grep -i "$PRIMARY_IF" /proc/interrupts | awk -F: '{gsub(/ /,"",$1);print $1}')
log "pinned $i ENA IRQs across $NCORES cores"

log "node-setup complete"
