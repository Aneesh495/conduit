# Virtual Networking and Service Discovery

Conduit includes a complete virtual networking fabric: deterministic IPAM addressing, virtual bridges, container DNS synthesis, and userspace TCP proxies.

## 1. IP Address Management (IPAM)

Conduit manages internal IPv4 address spaces without external daemon dependencies:

- Default Subnet: `10.88.0.0/16`
- Default Gateway: `10.88.0.1`
- Host Address Pool: `10.88.0.2` to `10.88.255.254`

Leases are persisted in `${CONDUIT_NETWORKS_DIR}/<net_name>/leases.txt` using transactional atomic file replacements. Sequential allocations ensure deterministic IP assignment, while release hooks reclaim addresses upon container termination.

## 2. Linux Bridge and veth Pairs

When running with root privileges on Linux:
1. Conduit initializes a host software bridge named `conduit0` and assigns `10.88.0.1/16`.
2. For each container, Conduit creates a virtual ethernet pair (`veth<id>` and `peer<id>`).
3. `veth<id>` is enslaved to `conduit0`.
4. `peer<id>` is transferred into the container network namespace, renamed to `eth0`, and configured with the leased container IP.
5. Outbound internet access is enabled via iptables `MASQUERADE` NAT rules on the default host route.

## 3. Userspace Bidirectional TCP Proxy

On macOS Darwin and unprivileged Linux environments where kernel NAT and veth pairs are restricted, Conduit provides a userspace TCP proxy daemon:

```
+---------------+        +----------------------+        +-------------------+
|  Host Client  | ====>  | Conduit Proxy Daemon | ====>  | Container Service |
| 127.0.0.1:8080|        |  (select / threads)  |        |  localhost:80     |
+---------------+        +----------------------+        +-------------------+
```

- Each published port binding (`-p 8080:80`) starts an asynchronous background proxy process.
- Proxy process PIDs are tracked in `state/proxy_<port>.pid` and automatically terminated when the container is stopped.
- Supports ephemeral port allocation: specifying `-p 0:80` dynamically queries and reserves an unallocated port in the range 49152-65535.

## 4. Service Discovery and `/etc/hosts` Synthesis

Within multi-service topologies orchestrated by `conduit compose`, containers discover sibling services through synthesized `/etc/hosts` tables:

```
127.0.0.1   localhost
::1         localhost ip6-localhost
10.88.0.2   web_gateway_1 gateway
10.88.0.3   web_backend_1 backend
10.88.0.4   web_redis_1   redis
```

This allows services to communicate using standard DNS hostnames (e.g. `http://backend:8080` or `redis:6379`) without deploying an external CoreDNS or BIND server.
