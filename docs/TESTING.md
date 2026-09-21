# Test and Verification Plan

The original notebook's test-plan cell was ten bullet points reading "Input:
X / Output: Y" without a single concrete command -- true of any system,
useful for none. The plan below replaces each with an actual command or
observable outcome for this design.

1. **Node bring-up.** `kubectl get nodes -o wide` shows exactly three Ready
   nodes (fog-srv1, fog-agent1, fog-agent2) -- the LB nodes are deliberately
   not k3s nodes at all.
2. **VIP failover.** Stop keepalived on edge-lb1; confirm via `ip addr show`
   that 192.168.50.10 migrates to edge-lb2 within one advertisement
   interval, and that a request loop against the VIP shows no failed
   requests throughout.
3. **HAProxy backend health-checking.** Stop k3s on fog-agent1; confirm
   HAProxy's `show stat` (via the loopback stats socket) marks that backend
   down and traffic continues through the remaining nodes with no
   client-visible errors.
4. **MQTT end-to-end.** `mosquitto_pub`/`mosquitto_sub` against the VIP on
   8883 with TLS and valid credentials delivers a message end-to-end; the
   same attempt without credentials is rejected.
5. **Edge-processing pipeline.** Publish N synthetic sensor readings; confirm
   N corresponding points appear in InfluxDB within expected latency, and
   that the Grafana panel reflects them.
6. **Broker failover and persistence.** Delete the Mosquitto pod; confirm
   k3s reschedules it, the PVC reattaches, and persisted/retained state
   survives -- and explicitly document what does not survive (e.g. QoS0
   messages in flight at the moment of the kill).
7. **Config validation, repeatable.** `haproxy -c -f haproxy/haproxy.cfg` and
   `keepalived -t -f <config>` both exit 0; every manifest under `k8s/`
   passes schema validation against the target Kubernetes version.
8. **Security checks.** SSH password authentication is refused; an anonymous
   MQTT publish is refused; a port scan of the VIP from outside the LB
   nodes' allowed source ranges shows only 80/443/8883 open.
9. **Load.** A synthetic load tool against the HTTP path shows HAProxy's
   `show stat` connection counters distributing across the fog nodes roughly
   as expected at the target sensor/client count.
10. **Disaster recovery.** Simulate a full power loss on the fog cluster;
    confirm data on the external SSD survives, and that the documented
    re-join procedure (`docs/ARCHITECTURE.md`'s bring-up order) brings the
    cluster back with InfluxDB/Grafana data intact.

## How this repo's own configuration was verified

Every configuration file in this repo was run through its actual validator
rather than only read for plausibility:

- `haproxy -c` against `haproxy/haproxy.cfg`
- `keepalived -t` against both `keepalived/*.conf`
- every Kubernetes manifest parsed with PyYAML, then schema-checked with
  [kubeconform](https://github.com/yannh/kubeconform) against the live
  Kubernetes 1.35.7 API (the version shipped in the k3s stable release used
  as the reference for this project, v1.35.7+k3s1) -- 15 of 15 real
  Kubernetes resources validated
- the architecture diagram was rendered from its Mermaid source rather than
  hand-drawn
- both shell scripts were checked with `bash -n`

The one file kubeconform cannot check is `k8s/05-traefik-config.yaml`'s
`HelmChartConfig` -- a k3s-specific custom resource, not part of the core
Kubernetes schema catalog -- which was instead checked directly against
k3s's own documentation (see [`REFERENCES.md`](REFERENCES.md)).

That process caught the three issues listed at the bottom of
[`ERRATA.md`](ERRATA.md), fixed before anything was committed.
