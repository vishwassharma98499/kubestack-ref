# ADR 002: ArgoCD over FluxCD

## Status

Accepted

## Context

We need a GitOps controller to continuously reconcile Kubernetes manifests from Git. The two leading options are ArgoCD and FluxCD (v2).

Key considerations:
- The team includes engineers with varying Kubernetes experience
- We need clear visibility into deployment status and drift detection
- The platform will be demonstrated to stakeholders and in interviews
- We manage both platform components (Helm charts) and application workloads

## Decision

Use **ArgoCD** as the GitOps controller.

## Consequences

### Positive
- **Web UI**: ArgoCD provides an excellent dashboard showing application topology, sync status, health, and diff views. This is valuable for debugging and for demonstrating the platform
- **App-of-apps pattern**: ArgoCD's Application CRD enables a hierarchical management model where a single root Application manages all other Applications
- **Multi-source support**: A single ArgoCD Application can pull from a Helm repo and a Git repo simultaneously (used for cert-manager + ClusterIssuer)
- **RBAC**: ArgoCD has built-in project-level RBAC, letting us restrict which namespaces and resources different teams can deploy
- **Ecosystem**: Large community, extensive documentation, and wide adoption in the German enterprise market (Siemens, BMW, SAP all use ArgoCD)

### Negative
- **Resource overhead**: ArgoCD HA mode runs multiple replicas of the controller, server, repo-server, and Redis — heavier than FluxCD
- **CRD complexity**: ArgoCD introduces Application, AppProject, and ApplicationSet CRDs
- **Pull-based only**: ArgoCD polls Git (or uses webhooks) — no native push-based reconciliation

### Alternatives Considered
- **FluxCD v2**: Lighter footprint, native Kustomize/Helm support, and tighter Git integration. However, it lacks a built-in UI (requires Weave GitOps or similar), which reduces visibility for the team
- **Jenkins X / Spinnaker**: Over-engineered for our use case and more complex to operate

### Mitigations
- Resource overhead is managed by right-sizing ArgoCD replicas per environment (HA in prod, single replica in dev)
- CRD complexity is manageable with the app-of-apps pattern — engineers rarely interact with ArgoCD CRDs directly
