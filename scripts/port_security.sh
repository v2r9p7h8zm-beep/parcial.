
#!/bin/sh
# Monitor de aprendizaje FDB para Open vSwitch. Adaptacion, NO Cisco IOS.
BRIDGE="br0"
LOG="/root/port_security_violations.log"
echo "Port-security monitor iniciado: $(date)" >> "$LOG"
while true; do
  for PORT in 2 3 4; do
    COUNT=$(ovs-appctl fdb/show "$BRIDGE" | awk -v p="$PORT" '$1 == p {print $3}' | sort -u | wc -l)
    if [ "$COUNT" -gt 2 ]; then
      IFACE="eth$((PORT-1))"
      echo "$(date): VIOLACION - $IFACE detecto $COUNT MAC. Puerto deshabilitado." >> "$LOG"
      ovs-ofctl mod-port "$BRIDGE" "$IFACE" down
    fi
  done
  sleep 2
done
