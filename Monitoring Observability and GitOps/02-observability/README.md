# Observability - Metrics, Logs and Traces

**Name:** Abhi Gandhi
**Enrollment Number:** 24bcs10397

This is my write-up for Task 2. Everything I describe here is also running on my
`abhi-devops` kind cluster: the hands-on part (commands, output and screenshots) is in
[Task 2 of the main README](../README.md#task-2-observability).

Files in this folder:

| File | What it is |
|---|---|
| [jaeger.yaml](jaeger.yaml) | Jaeger v2 all-in-one (in-memory) that receives OpenTelemetry (OTLP) traces |
| [traces.sh](traces.sh) | Small helper that queries the Jaeger API and prints a trace as a span tree |

## 1. Monitoring vs observability

I used to think these were the same word. After this session the difference I would give is:

- **Monitoring** answers questions I already knew to ask. I decide in advance "alert me if
  the Pod is down or CPU is above 80%", put that on a dashboard, and get paged. It tells
  me **that** something is wrong.
- **Observability** is a property of the system: how well I can understand its internal
  state from the data it emits, including for failures I never predicted. It helps me find
  **why** something is wrong, without shipping new code to add more debugging.

Monitoring is a subset of observability. You cannot have good observability without good
monitoring, but a wall of green dashboards does not mean the system is observable.

| | Monitoring | Observability |
|---|---|---|
| Question | Is it broken? | Why is it broken, and where? |
| Failures | Known failure modes ("known unknowns") | New, unexpected failures ("unknown unknowns") |
| Data | Mostly pre-aggregated metrics + fixed dashboards | Metrics + logs + traces with rich context, explored ad hoc |
| Output | Alerts, dashboards | Root cause, debugging, understanding of behaviour |
| Example | `PodinfoDeploymentDown` fires | The trace shows the 180 ms is spent waiting inside `podinfo-backend` |

## 2. The three pillars

### Metrics

A metric is a **number measured over time**, with labels. For example
`http_requests_total{service="podinfo-backend", status="200"} 1532`.

- Cheap to store and fast to query, because each sample is just a timestamp and a float.
  That is why metrics are what alerts are built on.
- Aggregatable: I can sum, average, take rates and percentiles across thousands of Pods.
- Low detail: a metric tells me the error rate went up, not which request failed.
- Prometheus metric types: **counter** (only goes up, e.g. requests served - I always use
  `rate()` on it), **gauge** (goes up and down, e.g. memory in use), **histogram** (counts
  in buckets, used for latency percentiles with `histogram_quantile`) and **summary**.
- Good starting sets: the **RED** method for services (Rate, Errors, Duration) and the
  **USE** method for resources (Utilization, Saturation, Errors).

In my demo: `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`
(from the kubelet's cAdvisor), `kube_deployment_status_replicas_available` (from
kube-state-metrics), `node_cpu_seconds_total` (node-exporter) and podinfo's own
`http_requests_total` / `http_request_duration_seconds`.

### Logs

A log is a **timestamped record of a discrete event** written by the application, e.g.
`{"level":"debug","msg":"request started","uri":"/echo","method":"POST","trace_id":"..."}`.

- Highest detail: exact error messages, stack traces, request parameters.
- Expensive at volume, and hard to aggregate unless they are **structured** (JSON) - podinfo
  logs JSON, which is why I can `grep` and count by `msg` easily.
- In Kubernetes, containers write to stdout/stderr; the kubelet keeps those files on the node
  and `kubectl logs` reads them. They disappear with the Pod, so a log pipeline (agent on each
  node -> central store) is needed. In my demo **Grafana Alloy** runs as a DaemonSet, tails
  every container log, adds `namespace/pod/container/app` labels and pushes to **Loki**.

### Traces

A trace follows **one request across every service it touches**.

- A trace is a tree of **spans**. Each span is one unit of work (an HTTP handler, an outgoing
  call, a DB query) with a start time, duration, status and attributes.
- All spans of one request share a **trace ID**; each span has its own span ID and a parent.
  The IDs travel between services in HTTP headers (W3C `traceparent`), which is called
  **context propagation**.
- Traces answer "where did the time go?" and "which hop failed?" - something neither metrics
  nor logs can answer on their own in a microservice system.
- Usually **sampled** (e.g. keep 1-10% of traces) because recording every span is costly.

In my demo, podinfo-frontend calls podinfo-backend. Both are instrumented with
OpenTelemetry and export spans over OTLP to Jaeger. A single `POST /echo` produces 9 spans
across the two services, and I can see the backend's artificial 20-200 ms random delay as the
gap before its `echoHandler` span.

### How they fit together

| | Metrics | Logs | Traces |
|---|---|---|---|
| Answers | What / how much / is it normal? | What exactly happened? | Where in the call chain? |
| Cost | Low | High | Medium (sampled) |
| Cardinality | Must stay low | Any | Any |
| Typical use | Alerts, dashboards, SLOs | Debugging a specific event | Latency analysis, dependency mapping |
| My tool | Prometheus + Grafana | Loki (+ Alloy) + Grafana | Jaeger (+ OpenTelemetry SDK in podinfo) |

The real power is **correlation**. My usual debugging flow, which I actually ran in the demo:

1. A **metric** / alert says something is off (request rate spike, latency up).
2. I open the **logs** for that service and time window. podinfo puts a `trace_id` in every
   request log line.
3. I paste that `trace_id` into Jaeger and get the full **trace**, which shows exactly which
   service and which step was slow.

## 3. Why observability is required

- **Distributed systems fail in new ways.** One user request can touch many Pods across
  nodes. Without traces I cannot tell which hop is slow; without central logs I would have
  to `kubectl logs` every Pod one by one.
- **Pods are ephemeral.** When a Pod is rescheduled or crashes, its logs and local state go
  with it. A crash at 3 a.m. is only debuggable if the data was shipped somewhere first.
- **Lower MTTD/MTTR.** Good signals reduce mean time to detect (alerts) and mean time to
  resolve (find the root cause quickly instead of guessing).
- **Autoscaling and capacity planning.** HPA, right-sizing requests/limits and node sizing
  all depend on CPU/memory metrics.
- **SLOs and user experience.** Uptime is not enough; I need request success rate and
  latency percentiles to know whether users are actually happy.
- **Safe deployments.** After a rollout (or an Argo CD sync) metrics show immediately if the
  new version increased errors, which is the signal to roll back.

## 4. Common tools

| Area | Tools |
|---|---|
| Instrumentation standard | **OpenTelemetry** (SDKs + OTLP protocol + Collector) - vendor-neutral, covers metrics, logs and traces |
| Metrics | **Prometheus**, Thanos / Cortex / Mimir (long-term, HA), VictoriaMetrics, Datadog, CloudWatch |
| Visualisation | **Grafana**, Kibana, Datadog dashboards |
| Alerting | **Alertmanager**, Grafana Alerting, PagerDuty / Opsgenie (on-call routing) |
| Logs | **Loki**, ELK / EFK (Elasticsearch + Logstash/Fluentd/Fluent Bit + Kibana), OpenSearch, Splunk |
| Log shippers | **Grafana Alloy**, Promtail (deprecated), Fluent Bit, Fluentd, Vector |
| Traces | **Jaeger**, Grafana Tempo, Zipkin, AWS X-Ray |
| All-in-one SaaS | Datadog, New Relic, Dynatrace, Honeycomb, Elastic Observability |

The open-source "LGTM" stack is Loki (logs), Grafana (UI), Tempo (traces) and Mimir
(metrics). I used Jaeger instead of Tempo because it ships a ready-made UI and runs as one
container.

## 5. Kubernetes observability

What I need to watch in a cluster, and where each signal comes from:

| Layer | Signal | Source in my cluster |
|---|---|---|
| Nodes | CPU, memory, disk, network | **node-exporter** DaemonSet (`node_*` metrics) |
| Containers | CPU, memory, throttling, restarts | **kubelet / cAdvisor** (`container_*`), scraped by Prometheus |
| Kubernetes objects | Desired vs available replicas, Pod phase, restarts, requests/limits | **kube-state-metrics** (`kube_*`) |
| Control plane | API server latency and errors | `apiserver` target (etcd/scheduler/controller-manager are bound to localhost in kind, so I disabled them) |
| Quick live view | `kubectl top` | **metrics-server** (Metrics API, also used by HPA) |
| Application | RED metrics, health endpoints | the app's own `/metrics`, `/healthz`, `/readyz` + liveness/readiness probes |
| Events | Scheduling failures, OOMKilled, image pull errors | `kubectl get events`, `kubectl describe` |
| Logs | stdout/stderr of every container | `kubectl logs`, Alloy -> Loki |
| Traces | request flow between services | OpenTelemetry SDK -> OTLP -> Jaeger |

Kubernetes-specific pieces that make this work:

- **Prometheus Operator** (from kube-prometheus-stack) adds CRDs so monitoring is declarative:
  a `ServiceMonitor` says "scrape Services with label `app=podinfo` on port `http`", a
  `PrometheusRule` holds alert rules. The operator turns them into Prometheus config, so
  monitoring config lives next to the app manifests (and can be managed by GitOps too).
- **Labels** are the glue: the same `namespace`, `pod`, `app` labels appear on metrics (from
  service discovery), on Loki log streams (added by Alloy) and on traces (resource
  attributes), which is what makes jumping between pillars possible.
- **Probes** are the cluster's own health checks: a failing readiness probe removes the Pod
  from Service endpoints, a failing liveness probe restarts the container. Their results are
  visible as metrics (`prober_probe_total`) and events.
- **Grafana sidecar** loads dashboards from ConfigMaps with label `grafana_dashboard=1`, so
  dashboards are code as well.

## 6. What I set up

```text
                 +---------------------------- namespace: monitoring ----------------------------+
                 |  Prometheus  <-- ServiceMonitor/PrometheusRule (Prometheus Operator)           |
 metrics  -----> |      |  alerts -> Alertmanager                                                 |
                 |      v                                                                         |
                 |   Grafana  (data sources: Prometheus, Loki, Jaeger, Alertmanager)              |
 logs     -----> |   Loki  <-- Alloy DaemonSet (tails /var/log/pods on every node)               |
                 +--------------------------------------------------------------------------------+
                 +--------------------------- namespace: observability --------------------------+
                 |  traffic --> podinfo-frontend --(HTTP + traceparent)--> podinfo-backend        |
                 |                 |  /metrics  JSON logs  OTLP spans          |                  |
 traces   -----> |                 +------------------------------------------> Jaeger           |
                 +--------------------------------------------------------------------------------+
```

**What I understood:** metrics told me *that* traffic spiked or a deployment went down,
logs told me *what* each Pod was doing, and the trace told me *where* inside the
frontend -> backend call the time was spent. The `trace_id` printed in the log line is the
bridge between the pillars, and Kubernetes labels are the bridge between the tools.
