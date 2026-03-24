# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-03-22

### Added

- **Go microservice** (`app/`) with `/healthz`, `/readyz`, `/info` endpoints, Prometheus metrics, structured JSON logging, graceful shutdown, and multi-stage Dockerfile (distroless runtime)
- **Local K3d stack** — one-command setup: `make demo` brings up a real Kubernetes cluster with ArgoCD, Prometheus, Grafana, NGINX Ingress, and the sample API
- **Terraform modules** for production AWS: VPC (3 AZ, public/private subnets, NAT), EKS (managed node groups, OIDC/IRSA, KMS encryption), RDS PostgreSQL (encryption, Multi-AZ, backups), S3 (versioning, encryption, lifecycle), ECR (scanning, lifecycle), IAM (IRSA roles), Security Groups
- **Kubernetes manifests** with production best practices: pod anti-affinity, HPA, PDB, resource limits, read-only rootfs, non-root containers, security contexts
- **Monitoring** — Prometheus stack with 2 custom Grafana dashboards (cluster overview + application metrics) and alerting rules (crash loops, high CPU/memory, 5xx rate, latency, cert expiry)
- **Security** — OPA Gatekeeper constraint templates (require labels, deny privileged, require resource limits, allowed registries), network policies (default deny + explicit allow)
- **CI/CD pipeline** — GitHub Actions with Terraform validation, kubeconform linting, tfsec + trivy scanning, Docker build + smoke test, full K3d integration test
- **GitHub Codespaces** support via `.devcontainer` — zero-install demo environment
- **Documentation** — Architecture (Mermaid diagrams), Runbook, Security Model, Cost Optimization, 3 Architecture Decision Records
- **Smoke test suite** (`make demo-test`) validating all components end-to-end
