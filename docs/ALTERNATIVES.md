# Alternatives Considered

The original notebook's alternatives section was mostly sound in spirit but
listed HAProxy as an alternative to itself (errata #13) -- dropped here. The
comparisons below are the ones that actually matter for this design.

**External HAProxy + keepalived vs. MetalLB / kube-vip.** MetalLB (or
kube-vip) hands a real virtual IP to an in-cluster Service and is the more
"Kubernetes-native" answer -- but it also removes the actual load-balancer
component from a project whose point is to build one. This design keeps
HAProxy/keepalived as the external HA boundary and disables k3s's competing
ServiceLB; MetalLB remains a reasonable path if you later want the LB tier
itself inside the cluster.

**InfluxDB 2 OSS vs. InfluxDB 3 Core.** As of 2026, InfluxDB 2 OSS is in
maintenance mode (stable, fully open-source, no new v3 features) while
InfluxDB 3 Core is InfluxData's forward-looking open-source, single-node
edition -- but it dropped the Flux query language and has no supported
migration path from v2. This design uses InfluxDB 2 OSS for a bounded
project's stability and documentation depth; re-evaluate InfluxDB 3 Core if
the project has a longer future ahead of it.

**Mosquitto vs. EMQX / VerneMQ.** Mosquitto is the simpler, lower-resource
single-broker choice this design uses. EMQX and VerneMQ support real
multi-node broker clustering with session-aware load balancing (HAProxy
stick-tables keyed on the MQTT client identifier, in EMQX's own documented
pattern) -- the right upgrade if a single broker's throughput becomes the
bottleneck, at the cost of materially more operational complexity than a
Raspberry Pi lab project needs on day one.

**k3s vs. full/kubeadm Kubernetes.** Full Kubernetes brings a larger
ecosystem and community at a real memory/CPU cost that matters on 4-8GB
boards; k3s trims exactly the components (etcd by default, alpha features,
in-tree cloud provider code, ...) that a single-site cluster like this one
does not need.

**On-prem fog cluster vs. a managed IoT cloud service.** AWS IoT Greengrass
or Azure IoT Edge would remove almost all of the infrastructure work this
repo is about, in exchange for recurring cost and a dependency on
connectivity to the provider. Reasonable for a production deployment;
contrary to the point of a hands-on infrastructure project.
