# Architecture

## Overview

kubestack-ref provisions a complete AWS infrastructure stack using Terraform and manages Kubernetes workloads through a GitOps pipeline powered by ArgoCD. All changes flow through Git — infrastructure changes via Terraform PRs, application changes via Kubernetes manifest PRs.

## Network Topology

```mermaid
graph TB
    subgraph "AWS Region: eu-central-1"
        subgraph "VPC (10.x.0.0/16)"
            subgraph "Public Subnets"
                IGW[Internet Gateway]
                ALB[Application Load Balancer]
                NAT[NAT Gateway]
            end
            subgraph "Private Subnets (AZ-a, AZ-b, AZ-c)"
                EKS[EKS Control Plane]
                NG[Node Group]
                RDS[(RDS PostgreSQL)]
            end
        end
        S3[(S3 Buckets)]
        ECR[(ECR Registry)]
        R53[Route53]
        ACM[ACM Certificates]
        CW[CloudWatch]
    end

    Internet --> R53
    R53 --> ALB
    ALB --> NG
    NG --> EKS
    NG --> RDS
    NG --> S3
    NG --> ECR
    NAT --> Internet
    NG --> NAT
    EKS --> CW
```

## GitOps Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant GA as GitHub Actions
    participant TF as Terraform
    participant AWS as AWS
    participant Argo as ArgoCD
    participant K8s as Kubernetes

    Dev->>GH: Push PR (terraform/ changes)
    GH->>GA: Trigger terraform-plan.yml
    GA->>TF: fmt + validate + plan
    GA->>GH: Post plan as PR comment
    Dev->>GH: Merge to main
    GH->>GA: Trigger terraform-apply.yml
    GA->>TF: apply
    TF->>AWS: Provision/update resources

    Dev->>GH: Push PR (kubernetes/ changes)
    GH->>GA: Trigger k8s-lint.yml + security-scan.yml
    Dev->>GH: Merge to main
    GH-->>Argo: Webhook / poll detects change
    Argo->>K8s: Sync manifests to cluster
    K8s-->>Argo: Report health status
```

## Request Path

```mermaid
graph LR
    Client[Client] --> R53[Route53 DNS]
    R53 --> ALB[AWS ALB]
    ALB --> |TLS termination| NP[NodePort]
    NP --> SVC[ClusterIP Service]
    SVC --> POD1[Pod replica 1]
    SVC --> POD2[Pod replica 2]
    SVC --> POD3[Pod replica 3]
    POD1 --> RDS[(RDS PostgreSQL)]
    POD1 --> S3[(S3)]
```

## Component Interactions

| Component | Role | Managed By |
|-----------|------|-----------|
| VPC, Subnets, NAT | Network isolation | Terraform |
| EKS | Kubernetes control plane | Terraform |
| RDS PostgreSQL | Application database | Terraform |
| S3 | Asset storage + TF state | Terraform |
| ECR | Container image registry | Terraform |
| IAM / IRSA | Pod-level AWS permissions | Terraform |
| ArgoCD | GitOps continuous delivery | Helm (self-managed) |
| Prometheus + Grafana | Monitoring and dashboards | ArgoCD (Helm) |
| Fluent Bit | Log aggregation to CloudWatch | ArgoCD (Helm) |
| AWS LB Controller | Ingress ALB provisioning | ArgoCD (Helm) |
| ExternalDNS | DNS record management | ArgoCD (Helm) |
| cert-manager | TLS certificate automation | ArgoCD (Helm) |
| Sealed Secrets | Git-safe secret encryption | ArgoCD (Helm) |
| OPA Gatekeeper | Policy enforcement | ArgoCD (Helm) |
| Kubecost | Cost visibility | ArgoCD (Helm) |

## Environment Strategy

Three isolated environments share the same Terraform modules and Kubernetes base manifests, with per-environment overrides:

| Aspect | Dev | Staging | Prod |
|--------|-----|---------|------|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| Node type | t3.medium (SPOT) | t3.large (ON_DEMAND) | m5.large (ON_DEMAND) |
| Node count | 1–4 | 2–6 | 3–10 |
| RDS Multi-AZ | No | Yes | Yes |
| RDS class | db.t3.micro | db.t3.medium | db.r6g.large |
| VPC Flow Logs | Disabled | Enabled | Enabled |
| EKS API | Public | Public | Private |
| App replicas | 1 | 2 | 3 |
| Log level | debug | info | warn |
