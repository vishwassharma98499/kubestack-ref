# Operational Runbook

## Table of Contents

- [Scaling Nodes](#scaling-nodes)
- [Debugging a Failing Pod](#debugging-a-failing-pod)
- [Rolling Back a Deployment](#rolling-back-a-deployment)
- [Rotating Secrets](#rotating-secrets)
- [Certificate Issues](#certificate-issues)
- [High Error Rate Response](#high-error-rate-response)
- [Node Not Ready](#node-not-ready)
- [RDS Connection Issues](#rds-connection-issues)

---

## Scaling Nodes

### Manually adjust desired node count

```bash
# Check current node group status
aws eks describe-nodegroup \
  --cluster-name kubestack-ref-prod-eks \
  --nodegroup-name kubestack-ref-prod-general \
  --query 'nodegroup.scalingConfig'

# Scale up (within the min/max defined in Terraform)
aws eks update-nodegroup-config \
  --cluster-name kubestack-ref-prod-eks \
  --nodegroup-name kubestack-ref-prod-general \
  --scaling-config desiredSize=5
```

### Permanently change scaling limits

Update the `node_min_size`, `node_max_size`, and `node_desired_size` variables in the appropriate `terraform.tfvars`, then open a PR. The Terraform plan will show the scaling config change.

### Cluster Autoscaler note

If Cluster Autoscaler or Karpenter is deployed, node scaling is automatic. The HPA scales pods, which triggers pending pods, which triggers the autoscaler to add nodes.

---

## Debugging a Failing Pod

### Step 1: Identify the problem

```bash
# List pods and their status
kubectl get pods -n app -o wide

# Check events for the namespace
kubectl get events -n app --sort-by=.lastTimestamp | tail -20

# Describe the failing pod
kubectl describe pod <pod-name> -n app
```

### Step 2: Check logs

```bash
# Current container logs
kubectl logs <pod-name> -n app

# Previous container logs (if it crash-looped)
kubectl logs <pod-name> -n app --previous

# Follow logs in real-time
kubectl logs -f <pod-name> -n app
```

### Step 3: Common failure patterns

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `CrashLoopBackOff` | App crashes on startup | Check logs for stack trace; verify env vars and secrets |
| `ImagePullBackOff` | Wrong image tag or ECR auth | Verify image exists in ECR; check node IAM role |
| `Pending` | Insufficient resources | Check resource quotas; scale node group |
| `OOMKilled` | Memory limit exceeded | Increase memory limits in deployment |
| `CreateContainerConfigError` | Missing ConfigMap/Secret | Verify ConfigMap and SealedSecret exist |

### Step 4: Exec into pod (if running)

```bash
# Open a shell (if the container has one)
kubectl exec -it <pod-name> -n app -- /bin/sh

# For read-only rootfs, use /tmp for temporary files
kubectl exec -it <pod-name> -n app -- ls /tmp
```

---

## Rolling Back a Deployment

### Option 1: ArgoCD rollback (preferred)

```bash
# List deployment history
argocd app history sample-api

# Rollback to previous revision
argocd app rollback sample-api <revision-number>
```

### Option 2: Git revert (GitOps way)

```bash
# Revert the problematic commit
git revert <commit-sha>
git push origin main
# ArgoCD will automatically sync the revert
```

### Option 3: kubectl rollback (emergency)

```bash
# View rollout history
kubectl rollout history deployment/sample-api -n app

# Rollback to previous version
kubectl rollout undo deployment/sample-api -n app

# Rollback to a specific revision
kubectl rollout undo deployment/sample-api -n app --to-revision=3

# Verify the rollback
kubectl rollout status deployment/sample-api -n app
```

Note: After a kubectl rollback, ArgoCD will show the app as "OutOfSync". Either update Git to match the rolled-back state, or use `argocd app sync --prune` to re-sync from Git.

---

## Rotating Secrets

### Using the rotation script

```bash
./scripts/rotate-secrets.sh app sample-api-secrets
```

### Manual rotation

```bash
# 1. Create a new plaintext secret
kubectl create secret generic sample-api-secrets \
  --namespace=app \
  --from-literal=DB_HOST=new-host.rds.amazonaws.com \
  --from-literal=DB_PASSWORD=new-password-here \
  --dry-run=client -o json > /tmp/secret.json

# 2. Encrypt with kubeseal
kubeseal \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format yaml \
  < /tmp/secret.json \
  > kubernetes/apps/sample-api/sealed-secret.yaml

# 3. Clean up the plaintext
rm /tmp/secret.json

# 4. Commit and push
git add kubernetes/apps/sample-api/sealed-secret.yaml
git commit -m "chore: rotate sample-api secrets"
git push origin main
```

---

## Certificate Issues

### Check certificate status

```bash
kubectl get certificates -A
kubectl describe certificate <cert-name> -n <namespace>
kubectl get certificaterequests -A
kubectl get challenges -A
```

### Force certificate renewal

```bash
# Delete the certificate to trigger re-issuance
kubectl delete certificate <cert-name> -n <namespace>
# cert-manager will re-create it from the Ingress annotation
```

### Check cert-manager logs

```bash
kubectl logs -l app=cert-manager -n cert-manager --tail=50
```

---

## High Error Rate Response

When the `HighErrorRate` alert fires (5xx > 5%):

1. **Check pod health**: `kubectl get pods -n app` — any not Ready?
2. **Check recent deployments**: `kubectl rollout history deployment/sample-api -n app`
3. **Check application logs**: `kubectl logs -l app=sample-api -n app --tail=100`
4. **Check RDS connectivity**: Can pods reach the database?
5. **Check resource pressure**: `kubectl top pods -n app` — any at limits?
6. **If caused by a bad deploy**: Roll back (see above)
7. **If caused by load**: Verify HPA is scaling, check node capacity

---

## Node Not Ready

```bash
# Check node status
kubectl get nodes
kubectl describe node <node-name>

# Check system pods on that node
kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name>

# If node is draining or cordoned:
kubectl uncordon <node-name>

# If node needs replacement, cordon and drain:
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

---

## RDS Connection Issues

```bash
# Verify the RDS endpoint from Terraform output
cd terraform/environments/<env>
terraform output rds_endpoint

# Test connectivity from a pod
kubectl run -it --rm debug --image=postgres:16 -n app -- \
  psql "host=<rds-endpoint> port=5432 dbname=app user=app_admin sslmode=require"

# Check security group allows traffic from EKS nodes
aws ec2 describe-security-groups --group-ids <rds-sg-id> \
  --query 'SecurityGroups[].IpPermissions'
```
