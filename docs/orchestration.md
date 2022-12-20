# Multi-Service Orchestration and DAG Scheduling

Conduit includes a declarative multi-service orchestrator (`conduit compose`) capable of deploying complex microservice topologies with topological dependency resolution and zero-downtime rolling updates.

## 1. Directed Acyclic Graph (DAG) Scheduler

When parsing `conduit-compose.yml`, services form a Directed Acyclic Graph based on their `depends_on` constraints:

```
          [ database ]
               ^
               | depends_on
          [ backend ]
               ^
               | depends_on
          [ gateway ]
```

### Kahn's Topological Sort Algorithm
Conduit executes Kahn's algorithm in pure Bash to calculate deterministic execution tiers:
1. In-Degree Computation: For each service node, calculate the count of incoming dependency edges.
2. Queue Initialization: Nodes with in-degree 0 (services with no dependencies, e.g. `database`) are enqueued.
3. Iterative Resolution: Dequeue node $u$, append to execution schedule, and decrement the in-degree of all dependent neighbor nodes $v$. If in-degree of $v$ reaches 0, enqueue $v$.
4. Cycle Detection: If the count of scheduled nodes is less than the total node count, Conduit throws `ERR_DAG_CYCLE` (code 70) and outputs the cycle paths.

## 2. Health Check Readiness Gates

Starting a dependent container immediately after launching its prerequisite can cause startup connection race conditions (e.g. backend trying to connect to a database that is still initializing tables).

Conduit prevents this via health check readiness gates:
- A dependent container is blocked from spawning until the prerequisite passes its configured health probe.
- Probe protocols:
  - `http`: Polls endpoint and checks for HTTP 2xx/3xx response.
  - `tcp`: Probes TCP port listener readiness.
  - `exec`: Runs diagnostic check inside container and tests for exit status 0.
- If the prerequisite fails to become healthy within the configured timeout window, the deployment halts and rolls back.

## 3. Zero-Downtime Blue-Green Rolling Updates

During image upgrades (`conduit::rolling_update`), Conduit executes blue-green replacement:

1. Stage Green Instance: Launches the new container alongside the active production instance.
2. Health Check Barrier: The green container must pass all health probes before traffic is shifted.
3. Traffic Cutover: Virtual network proxy routes and `/etc/hosts` DNS records are atomically repointed to the green container IP.
4. Blue Decommission: The old blue instance receives graceful `SIGTERM`, waits for in-flight requests to complete, and is safely retired.
5. Automated Rollback: If the green instance crashes or fails health verification, Conduit automatically destroys green and preserves the blue container without any downtime.
