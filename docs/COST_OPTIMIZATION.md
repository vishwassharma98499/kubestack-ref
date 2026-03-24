# Cost Optimization Strategy

## Overview

kubestack-ref uses a tiered cost strategy: aggressive optimization in dev, balanced in staging, reliability-first in production. Cost visibility is provided through Kubecost, and the infrastructure is designed to minimize waste at every layer.

## Compute: Spot vs On-Demand

| Environment | Instance Type | Capacity | Rationale |
|-------------|--------------|----------|-----------|
| Dev | t3.medium | SPOT | Dev tolerates interruptions; ~70% savings |
| Staging | t3.large | ON_DEMAND | Staging mirrors prod behavior; needs stability |
| Prod | m5.large | ON_DEMAND | Production requires guaranteed capacity |

For production workloads that can tolerate interruptions (batch processing, CI runners), a separate SPOT node group can be added with appropriate taints and tolerations.

## Right-Sizing

### Node Groups
- Start with the minimum viable instance type per environment
- Monitor actual CPU/memory usage in Grafana dashboards
- Adjust `node_instance_types` in `terraform.tfvars` based on usage patterns
- Use `kubectl top nodes` to identify over-provisioned nodes

### Pod Resources
- All containers have explicit requests and limits (enforced by OPA Gatekeeper)
- HPA scales pods based on actual CPU/memory utilization
- Review Kubecost recommendations for right-sizing suggestions

### RDS
- Dev uses `db.t3.micro` — sufficient for development workloads
- Staging uses `db.t3.medium` — adequate for integration testing
- Prod uses `db.r6g.large` — memory-optimized for production queries
- Storage autoscaling configured with `max_allocated_storage`

## Storage Optimization

### S3 Lifecycle Policies
- Objects transition to STANDARD_IA after 90 days
- Non-current versions expire after 30 days
- Versioning enabled for data protection without unlimited retention

### EBS (Prometheus)
- Prometheus retention set to 15 days
- 50Gi storage with gp3 volumes (better $/IOPS than gp2)

## Network Cost Reduction

### Single NAT Gateway (Dev)
Dev environments use a single NAT Gateway. For production HA, deploy one per AZ (modify the VPC module's `enable_nat_gateway` logic).

### VPC Flow Logs
Disabled in dev to avoid CloudWatch ingestion costs. Enabled in staging/prod for security compliance.

## Kubecost

Kubecost is deployed in every environment to provide:
- Per-namespace cost breakdowns
- Per-deployment cost attribution
- Right-sizing recommendations
- Idle resource detection
- Cost anomaly alerting

### Accessing Kubecost

```bash
kubectl port-forward svc/kubecost-cost-analyzer 9090:9090 -n kubecost
# Open http://localhost:9090
```

### Cost reporting script

```bash
./scripts/cost-report.sh 7d    # Last 7 days
./scripts/cost-report.sh 30d   # Last 30 days
```

## Monthly Cost Estimates (eu-central-1)

These are rough estimates for a minimal deployment:

| Resource | Dev | Staging | Prod |
|----------|-----|---------|------|
| EKS control plane | $73 | $73 | $73 |
| EC2 nodes (2×t3.medium SPOT) | ~$30 | ~$120 (ON_DEMAND) | ~$280 (3×m5.large) |
| NAT Gateway | $32 + data | $32 + data | $32 + data |
| RDS (db.t3.micro) | $15 | $70 (t3.medium, Multi-AZ) | $400 (r6g.large, Multi-AZ) |
| S3 | <$1 | <$5 | <$20 |
| CloudWatch | <$5 | ~$20 | ~$50 |
| **Estimated Total** | **~$155/mo** | **~$320/mo** | **~$855/mo** |

Note: Actual costs vary significantly based on data transfer, storage usage, and workload intensity.

## Cost Alerts

Set up AWS Budgets alongside Kubecost:

```bash
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget '{
    "BudgetName": "kubestack-ref-monthly",
    "BudgetLimit": {"Amount": "500", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80
    },
    "Subscribers": [{
      "SubscriptionType": "EMAIL",
      "Address": "team@example.com"
    }]
  }]'
```
