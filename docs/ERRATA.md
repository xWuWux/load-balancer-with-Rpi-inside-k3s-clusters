# Errata in the Original Concept

The original material (`load balancer with Rpi inside k3s clusters.ipynb`, an
AI-assisted brainstorm later saved into this repo) had 13 concrete, checkable
problems -- not style issues, things that don't work. Each is stated with
what was written and why it fails.

1. **Cluster-join command does not exist.** The notebook's
   `sudo k3s server join --token=<token> https://<master_node_ip>:6443` is
   not a real k3s subcommand -- there is no `k3s server join`. Agents join
   via the `K3S_URL` / `K3S_TOKEN` environment variables on the install
   one-liner; additional control-plane nodes join with
   `k3s server --server https://<master-ip>:6443`. See `scripts/setup-node.sh`.

2. **The one Raspberry-Pi-specific setting k3s actually needs is missing.**
   kubelet requires the memory cgroup controller, which is not enabled by
   default on Raspberry Pi OS. The notebook's Rpi configuration steps never
   mention this at all; without it k3s either fails outright or runs
   degraded. The fix is a boot-parameter edit (`/boot/firmware/cmdline.txt`)
   plus a reboot, done once per node before installing k3s.

3. **Two contradictory load-balancer designs presented as one.** HAProxy is
   first installed as an OS package directly on a Raspberry Pi, then -- a
   few cells later -- redefined as a Kubernetes Deployment sitting behind
   its own `type: LoadBalancer` Service inside the same K3s cluster it is
   supposed to be fronting. That is circular: the thing meant to be the
   entry point to the cluster cannot itself be reached until something else
   already fronts the cluster.

4. **Three overlapping load-balancing layers with no stated division of
   labour.** Between the HAProxy config, the Nginx `upstream`/`proxy_pass`
   reverse-proxy config, and Kubernetes' own Service/kube-proxy balancing,
   the same job (spreading HTTP requests across backends) is done three
   times by three different tools in the same notebook, with no explanation
   of which one is actually in charge of what.

5. **HAProxy config contains copy-paste artifacts, not valid syntax.** The
   `server` lines (in the chat transcript this notebook was saved from) read
   `server web1 [192.168.1.100:80](http://192.168.1.100:80) check` --
   literal Markdown hyperlink syntax from the chat UI's auto-linking, pasted
   back into the config verbatim. This is not valid HAProxy syntax and fails
   `haproxy -c` immediately.

6. **An incomplete Kubernetes Service manifest.** `web-server-service.yaml`
   (cell 21) is shown with a `selector` and nothing else -- no `ports:`
   block, so even if applied it would not forward any traffic.

7. **No protocol awareness anywhere in the load-balancing design.** Every
   example assumes plain HTTP round robin. Given the project's own IoT
   framing, the first real IoT traffic this design would meet is MQTT -- a
   stateful, connection-oriented protocol -- and naive HTTP-style balancing
   across independent broker processes silently breaks retained messages and
   in-flight QoS state. This is never considered.

8. **Undisclosed, undiscussed dependency on k3s's bundled ServiceLB.** A
   `type: LoadBalancer` Service on stock k3s is actually served by the
   bundled "Klipper" controller (a per-node hostPort DaemonSet), not a real
   virtual IP. The notebook uses `type: LoadBalancer` without ever naming
   this mechanism, discussing its limits, or comparing it against the
   alternatives (MetalLB, kube-vip) -- notable, given the entire exercise is
   nominally about building a load balancer.

9. **No IoT data path exists despite the IoT framing.** "IoT", "edge" and
   "fog" appear throughout the conversation's framing, but the concrete
   build is a generic Nginx placeholder page behind a load balancer -- no
   sensor, no MQTT broker, no edge-processing step, no time-series storage.
   The label and the implementation do not match.

10. **Security section is generic checklist text.** "Use a firewall", "use a
    VPN", "use an IDPS" -- true of nearly any networked system and
    actionable for none of them. No mention of the specific ports
    k3s/flannel actually use, no MQTT authentication story (there being no
    MQTT at all), no concrete firewall rule.

11. **Outdated OS name.** "Raspbian" was renamed Raspberry Pi OS in 2020;
    current guidance and packages use the new name.

12. **The diagrams carry no information.** Every requested "schematic",
    "block diagram", "flowchart" and "infrastructure drawing" renders the
    same four boxes (Internet, Load Balancer, K3s Cluster, Web Server) in
    slightly different ASCII art, with literal placeholder text
    `IP: x.x.x.x` instead of any real address, port, or decision point --
    five separate diagram requests that add nothing to what the prose
    already said. Compare with `architecture.mmd` / the diagram in
    `README.md`.

13. **The alternatives section offers HAProxy as an alternative to
    HAProxy.** "Using a different load balancer solutions... such as F5,
    HAProxy, and Nginx" lists the very tool already chosen as one of its own
    alternatives -- a small but real logic error.

## Three more issues, caught by actually testing the fix (not just reading it)

Every file in this repo was run through its real validator before being
committed -- `haproxy -c`, `keepalived -t`, and schema validation of every
Kubernetes manifest against the live Kubernetes API -- rather than only
reviewed for plausibility. That process caught three further issues in this
repo's own first draft, fixed before anything was committed:

1. **keepalived refused to start at all.** `keepalived -t` failed both
   configs with "SECURITY VIOLATION - scripts are being executed but
   script_security not enabled" -- modern keepalived will not run a
   `vrrp_script` until `enable_script_security` is set in `global_defs`, and
   by default wants to run that script as an unprivileged `script_user`
   rather than root. Fixed by adding both, plus a one-time `useradd` step
   for that account (now in `scripts/setup-lb-node.sh`).

2. **The health-check script itself was silently wrong.** The natural first
   choice, `killall -0 haproxy`, sends a real signal to check a process's
   existence -- which an unprivileged `script_user` has no permission to do
   to a process owned by a different account (haproxy runs as user
   `haproxy`). It would have read as "down" even while haproxy was perfectly
   healthy. Replaced with `pidof haproxy`, which only reads `/proc` and
   needs no signal permission.

3. **TCP passthrough silently discarded the real client IP.** Because HTTPS
   is passed through in TCP mode (deliberately, so HAProxy never needs the
   TLS private key), Traefik would see every connection as coming from
   edge-lb1/edge-lb2, not the actual client -- fine for connectivity, wrong
   for logging, rate-limiting or IP allow-lists. Fixed by adding
   `send-proxy-v2` on the HAProxy server lines and configuring Traefik's
   websecure entrypoint to trust PROXY protocol from those two IPs
   specifically.

That is 16 concrete, checkable findings behind this redesign -- not opinions.
