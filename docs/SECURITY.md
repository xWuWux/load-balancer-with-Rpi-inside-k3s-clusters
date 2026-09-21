# Security appendix -- concrete commands backing docs/SECURITY.md's parent section

## 1. Certificates for MQTT (Mosquitto) and the dashboard Ingress

Lab-grade self-signed CA, good enough for a course project (swap for
cert-manager/Let's Encrypt-via-internal-CA if this goes further):

```bash
# CA
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
    -subj "/CN=fog-lab-ca" -out ca.crt

# Mosquitto server cert (CN must match how clients will address the broker,
# typically the VIP or a hostname you map to it)
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=192.168.50.10" -out server.csr
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days 825 -sha256 -out server.crt

kubectl -n fog create secret generic mosquitto-tls \
    --from-file=ca.crt=ca.crt --from-file=tls.crt=server.crt --from-file=tls.key=server.key

# Dashboard ingress cert (SANs for both hostnames)
openssl req -new -newkey rsa:2048 -nodes -keyout web.key \
    -subj "/CN=grafana.fog.local" \
    -addext "subjectAltName=DNS:grafana.fog.local,DNS:nodered.fog.local" \
    -out web.csr
openssl x509 -req -in web.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days 825 -sha256 -copy_extensions copy -out web.crt

kubectl -n fog create secret tls fog-dashboards-tls --cert=web.crt --key=web.key
```

Distribute `ca.crt` to anything that needs to trust these (MQTT clients,
browsers) rather than clicking through "insecure" warnings.

## 2. MQTT auth (no anonymous publish -- the original project had no MQTT at
   all, so no auth story either)

```bash
mosquitto_passwd -c passwd.txt sensors      # prompts for a password
mosquitto_passwd    passwd.txt dashboard    # append a second user
kubectl -n fog create secret generic mosquitto-passwd --from-file=passwd=passwd.txt
shred -u passwd.txt                          # don't leave the plaintext copy around
```

ACL (already baked into `k8s/10-mosquitto.yaml`'s ConfigMap): `sensors` may
only publish under `sensors/#`, `dashboard` may only subscribe.

## 3. Firewall rules (nftables/ufw) -- scoped by actual role, not "turn on a
   firewall" boilerplate

On **edge-lb1 / edge-lb2**:
```bash
ufw default deny incoming
ufw allow 22/tcp                      # SSH (key auth only -- see below)
ufw allow 80,443,8883/tcp             # public/LAN-facing service ports
ufw allow from 192.168.50.12 to any proto vrrp   # VRRP peer (mirror the .11 on lb2)
ufw enable
```

On **fog-srv1 / fog-agent1 / fog-agent2**, restrict the control-plane and
cluster-internal ports to the LB nodes and to each other -- do NOT open them
to the whole LAN:
```bash
ufw default deny incoming
ufw allow 22/tcp
ufw allow from 192.168.50.21,192.168.50.22,192.168.50.23 to any port 6443 proto tcp   # k3s API, cluster-internal
ufw allow from 192.168.50.21,192.168.50.22,192.168.50.23 to any port 8472 proto udp   # flannel VXLAN
ufw allow from 192.168.50.21,192.168.50.22,192.168.50.23 to any port 10250 proto tcp  # kubelet
ufw allow from 192.168.50.11,192.168.50.12 to any port 31080,31443 proto tcp          # Traefik NodePort, LB only
ufw allow from 192.168.50.11,192.168.50.12 to any port 30883 proto tcp               # Mosquitto NodePort, LB only
ufw enable
```

## 4. SSH / OS hardening

```bash
# on every Pi
sudo passwd -l pi || true                 # lock the default account if still present
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
sudo apt-get install -y fail2ban unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```
Use SSH keys (`ssh-copy-id`) before disabling password auth, obviously.

## 5. k3s secrets at rest

k3s encrypts Secrets in its embedded datastore with a local key by default.
For anything beyond a course project, rotate/manage it explicitly:
```bash
sudo k3s secrets-encrypt status
sudo k3s secrets-encrypt rotate
```
or manage app secrets outside git entirely with SOPS+age if you adopt GitOps.

## 6. Physical

These are small, easily-pocketed boards sitting on a desk/shelf: use a
lockable enclosure or cabinet, and don't leave a monitor logged into
`kubectl`/Grafana-as-admin unattended. Raspberry Pi OS/most SD cards offer no
real protection against someone with physical access pulling the card, so
treat physical access as equivalent to root access -- this is a genuine
limitation of the platform, not something to paper over with a policy bullet.
