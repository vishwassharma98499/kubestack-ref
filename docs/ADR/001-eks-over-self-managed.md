# ADR 001: EKS over Self-Managed Kubernetes

## Status

Accepted

## Context

We need a Kubernetes cluster on AWS. The two primary options are Amazon EKS (managed control plane) and self-managed Kubernetes using tools like kops or kubeadm on EC2 instances.

Key considerations:
- The team operates a small platform engineering group (2–4 engineers)
- Uptime requirements are strict for production workloads
- The team needs to focus on application delivery, not cluster operations
- AWS is the sole cloud provider — no multi-cloud requirement

## Decision

Use **Amazon EKS** with managed node groups.

## Consequences

### Positive
- **Reduced operational burden**: AWS manages the control plane (etcd, API server, scheduler, controller manager), including patching and high availability across three AZs
- **Managed node groups**: Automatic AMI updates and node draining during upgrades
- **Native AWS integration**: IRSA, ALB controller, VPC CNI, and CloudWatch work seamlessly
- **Compliance**: EKS is SOC 2, ISO 27001, and HIPAA eligible — simplifies audit conversations with enterprise customers
- **EKS add-ons**: Core components (VPC CNI, CoreDNS, kube-proxy) managed as add-ons with automatic updates

### Negative
- **Cost**: $73/month per cluster for the control plane, which self-managed avoids
- **Version lag**: EKS typically trails upstream Kubernetes by 1–2 minor versions
- **Less flexibility**: Some control plane configurations (e.g., custom admission controllers at the API server level) are not possible
- **Vendor lock-in**: While workloads are portable, the IAM/IRSA and ALB integrations tie us to AWS

### Mitigations
- The $73/month cost is negligible compared to the engineering time saved on control plane operations
- Version lag is acceptable — we don't need bleeding-edge Kubernetes features
- IRSA and ALB controller configurations are isolated in dedicated modules, making migration feasible if needed
