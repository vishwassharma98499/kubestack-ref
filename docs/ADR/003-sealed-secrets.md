# ADR 003: Sealed Secrets over External Secrets Operator

## Status

Accepted

## Context

We need to manage Kubernetes secrets in a GitOps-compatible way. Plaintext Secrets cannot be committed to Git. The main options are:

1. **Bitnami Sealed Secrets**: Encrypt secrets client-side; store encrypted SealedSecret in Git; controller decrypts in-cluster
2. **External Secrets Operator (ESO)**: Store secret values in an external provider (AWS Secrets Manager, Parameter Store); ESO syncs them into Kubernetes Secrets
3. **SOPS + age/KMS**: Encrypt secret files with Mozilla SOPS; decrypt during CI/CD or with a controller
4. **HashiCorp Vault**: Full secrets management platform with dynamic secrets, leasing, and rotation

## Decision

Use **Bitnami Sealed Secrets**.

## Consequences

### Positive
- **Git as single source of truth**: Encrypted secrets live in the same repo as all other manifests — no external dependency for secret values
- **Simplicity**: One controller, one CRD, one CLI tool (`kubeseal`). No external secret store to provision or manage
- **Offline encryption**: Developers can encrypt secrets locally without cluster access (using the public key)
- **Cost**: No additional AWS service costs (Secrets Manager charges per secret per month + API calls)
- **ArgoCD native**: SealedSecrets are regular Kubernetes resources that ArgoCD syncs like anything else

### Negative
- **Key rotation**: Sealed Secrets controller generates a new key pair periodically, but old SealedSecrets must be re-encrypted with the new key
- **No dynamic secrets**: Unlike Vault, Sealed Secrets are static — no automatic credential rotation
- **No centralized audit**: Secret access is only visible through Kubernetes audit logs, not a dedicated secrets UI
- **Cluster-scoped encryption**: SealedSecrets are encrypted for a specific cluster — migrating to a new cluster requires re-sealing

### Alternatives Considered
- **External Secrets Operator**: Better for organizations already using AWS Secrets Manager or Vault. Adds a runtime dependency on the external store — if Secrets Manager is unreachable, new pods can't start. For our use case, the added complexity isn't justified
- **HashiCorp Vault**: Best-in-class for enterprises needing dynamic secrets, PKI, and fine-grained access control. Significant operational overhead to run (or $$$  for HCP Vault). Overkill for our current scale
- **SOPS**: Good middle ground, but requires CI/CD pipeline integration for decryption. Less GitOps-native than Sealed Secrets

### Mitigations
- Key rotation is handled by the controller automatically; a rotation script (`scripts/rotate-secrets.sh`) simplifies re-sealing
- For future growth, migrating to ESO is straightforward — swap SealedSecret manifests for ExternalSecret manifests, deploy ESO, and configure the SecretStore
