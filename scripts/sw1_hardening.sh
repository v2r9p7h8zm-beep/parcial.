
#!/bin/sh
# CIS-inspired hardening for the Open vSwitch lab switch (SW1).
# Platform: Alpine Linux + Open vSwitch. This is NOT Cisco IOS port-security.
# Run as root on SW1: sh sw1_hardening.sh

set -eu

BRIDGE="br0"
REPORT_DIR="/root"
STAMP="$(date '+%Y%m%d_%H%M%S')"
REPORT="${REPORT_DIR}/sw1_hardening_report_${STAMP}.txt"

# Verified lab mapping:
# eth0 = uplink to R1 (keep enabled)
# eth1 = PC1, eth2 = SRV1, eth3 = ZBX1
# MACs are the observed endpoint MACs from this lab.
ACCESS_PORTS="2 3 4"
UNUSED_PORTS="5 6 7 8 9 10 11 12 13 14 15"

PC1_MAC="00:50:79:66:68:00"
SRV1_MAC="08:00:27:c7:5e:c5"
ZBX1_MAC="08:00:27:bf:3c:38"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $1" >&2
        exit 1
    }
}

need ovs-vsctl
need ovs-ofctl
need date
need tee

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run this script as root." >&2
    exit 1
fi

if ! ovs-vsctl br-exists "$BRIDGE"; then
    echo "ERROR: bridge $BRIDGE does not exist." >&2
    exit 1
fi

mkdir -p "$REPORT_DIR"

{
    echo "SW1 - POST-HARDENING REPORT"
    echo "Date: $(date)"
    echo "Bridge: $BRIDGE"
    echo "Platform: Alpine Linux / Open vSwitch"
    echo
    echo "Selected hardening controls:"
    echo "1. Static source-MAC allow-list on access ports (PC1/SRV1/ZBX1)."
    echo "2. Drop frames with any other source MAC on those access ports."
    echo "3. Disable unused switch ports eth4-eth15."
    echo "4. Preserve eth0 uplink to R1 and access to the management bridge."
    echo
    echo "NOTE: Open vSwitch implementation; not Cisco IOS port-security."
    echo "The allow-list blocks unknown MACs but does not implement automatic"
    echo "err-disable/shutdown after a MAC-count violation."
    echo
    echo "=== BEFORE: bridge and port status ==="
    ovs-vsctl show
    ovs-ofctl show "$BRIDGE"
    echo
    echo "=== APPLYING HARDENING ==="

    # Remove only rules on access ports, then rebuild the selected policy.
    ovs-ofctl del-flows "$BRIDGE" "in_port=2"
    ovs-ofctl del-flows "$BRIDGE" "in_port=3"
    ovs-ofctl del-flows "$BRIDGE" "in_port=4"

    # Permit the observed endpoint MAC and one reserved second MAC per port.
    # The reserved addresses allow a second authorized device if required.
    ovs-ofctl add-flow "$BRIDGE" \
      "priority=100,in_port=2,dl_src=${PC1_MAC},actions=NORMAL"
    ovs-ofctl add-flow "$BRIDGE" \
      "priority=100,in_port=2,dl_src=02:00:00:00:01:01,actions=NORMAL"
    ovs-ofctl add-flow "$BRIDGE" \
      "priority=90,in_port=2,actions=drop"

    ovs-ofctl add-flow "$BRIDGE" \
      "priority=100,in_port=3,dl_src=${SRV1_MAC},actions=NORMAL"
    ovs-ofctl add-flow "$BRIDGE" \
      "priority=100,in_port=3,dl_src=02:00:00:00:01:02,actions=NORMAL"
    ovs-ofctl add-flow "$BRIDGE" \
      "priority=90,in_port=3,actions=drop"

    ovs-ofctl add-flow "$BRIDGE" \
      "priority=100,in_port=4,dl_src=${ZBX1_MAC},actions=NORMAL"
    ovs-ofctl add-flow "$BRIDGE" \
      "priority=100,in_port=4,dl_src=02:00:00:00:01:03,actions=NORMAL"
    ovs-ofctl add-flow "$BRIDGE" \
      "priority=90,in_port=4,actions=drop"

    # Shut down unused ports only; never touch eth0-eth3.
    for p in $UNUSED_PORTS; do
        ovs-ofctl mod-port "$BRIDGE" "$p" down
    done

    echo "Hardening commands applied."
    echo
    echo "=== AFTER: OpenFlow policy ==="
    ovs-ofctl dump-flows "$BRIDGE"
    echo
    echo "=== AFTER: port status ==="
    ovs-ofctl show "$BRIDGE"
    echo
    echo "=== AFTER: bridge configuration ==="
    ovs-vsctl show
    echo
    echo "=== VERIFICATION SUMMARY ==="
    echo "Expected access policy:"
    echo "  Port 2 / eth1: allow ${PC1_MAC} and 02:00:00:00:01:01; drop other sources."
    echo "  Port 3 / eth2: allow ${SRV1_MAC} and 02:00:00:00:01:02; drop other sources."
    echo "  Port 4 / eth3: allow ${ZBX1_MAC} and 02:00:00:00:01:03; drop other sources."
    echo "Expected disabled ports: eth4-eth15."
    echo "Uplink eth0 and access ports eth1-eth3 are intentionally left enabled."
    echo
    echo "REPORT COMPLETE"
} 2>&1 | tee "$REPORT"

echo
echo "Report saved to: $REPORT"
