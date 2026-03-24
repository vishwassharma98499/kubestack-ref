# Security Model

## Overview

kubestack-ref implements defense-in-depth across four layers: IAM, network, policy enforcement, and secrets management. Every layer is codified — no manual configuration required.

## IAM & IRSA

Pods access AWS services through **IAM Roles for Service Accounts (IRSA)**, not static credentials. Each workload gets a dedicated IAM role with minimum-privilege permissions.

| Service Account | Namespace | AWS Permissions |
|----------------|-----------|----------------|
| `sample-api` | app | S3 read/write to assets bucket |
| `aws-load-balancer-controller` | ingress | EC2, ELB, ACM (ALB management) |
| `external-dns` | ingress | Route53 record management |
| `cert-manager` | cert-manager | Route53 (DNS-01 challenge) |

IRSA works through the EKS OIDC provider — Kubernetes tokens are exchanged for short-lived AWS credentials. No long-lived keys exist anywhere in the system.

## Network Security

### VPC Design
- **Public subnets**: ALB only — no workloads directly exposed
- **Private subnets**: EKS nodes and RDS — no public IP addresses
- **NAT Gateway**: Controlled egress for private subnets
- **VPC Flow Logs**: Enabled in staging/prod for audit trails

### Security Groups
- **EKS cluster SG**: Only accepts HTTPS (443) from worker nodes
- **Worker node SG**: Accepts traffic from control plane and ALB (NodePort range)
- **RDS SG**: Only accepts PostgreSQL (5432) from worker nodes
- **ALB SG**: Accepts HTTP/HTTPS from the internet

### Kubernetes Network Policies
- **Default deny** on all ingress and egress in the `app` namespace
- Explicit allow rules for: ingress controller traffic, DNS resolution, external HTTPS, RDS access, Prometheus scraping
- Each namespace is isolated by default

## Policy Enforcement (OPA Gatekeeper)

Four constraint templates enforce cluster-wide policies:

| Constraint | Scope | Action |
|-----------|-------|--------|
| `require-app-team-labels` | All pods, deployments | Reject if missing `app` or `team` labels |
| `deny-privileged-containers` | All pods | Reject privileged containers or privilege escalation |
| `require-resource-limits` | All pods | Reject if CPU/memory requests or limits are missing |
| `allowed-repos` | App namespace | Reject images not from our ECR |

System namespaces (`kube-system`, `gatekeeper-system`) are excluded to avoid blocking core components.

## Secrets Management

Secrets are managed with **Bitnami Sealed Secrets**:

1. Developer creates a plaintext Kubernetes Secret locally
2. `kubeseal` encrypts it with the cluster's public key
3. The `SealedSecret` YAML is committed to Git (safe — only the cluster can decrypt it)
4. The sealed-secrets controller decrypts it into a regular Secret at deploy time

This approach allows secrets to live in Git alongside all other configuration, maintaining the GitOps principle that Git is the single source of truth.

### Secret rotation
Use `./scripts/rotate-secrets.sh` to interactively rotate secret values and re-seal them.

## CI/CD Security Scanning

Every pull request runs three security scanners:

| Tool | What It Checks |
|------|---------------|
| **tfsec** | Terraform misconfigurations (open security groups, missing encryption, etc.) |
| **Checkov** | Policy-as-code for both Terraform and Kubernetes manifests |
| **Trivy** | Vulnerabilities and misconfigurations in IaC and container images |

Results are uploaded as SARIF to GitHub Security tab for tracking and trending.

## EKS Security

- **Secrets encryption**: Kubernetes secrets encrypted at rest with a dedicated KMS key
- **Control plane logging**: API, audit, authenticator, controller manager, and scheduler logs shipped to CloudWatch
- **Private API endpoint** in production — no public access to the Kubernetes API
- **Managed node groups**: Amazon Linux 2 AMIs with automatic patching
- **SSM access**: Nodes have SSM agent for emergency access without SSH keys

## Container Security

Every workload container is configured with:
- `runAsNonRoot: true` — no root processes
- `readOnlyRootFilesystem: true` — immutable container filesystem
- `allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]` — no Linux capabilities
- `seccompProfile.type: RuntimeDefault` — syscall filtering
