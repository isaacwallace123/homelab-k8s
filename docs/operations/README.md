# Operations

Operations documentation is for safely changing, recovering, and verifying the running platform.
Runbooks must include a precondition, an explicit change, verification, and a rollback or stop
condition. One-time migration procedures are not routine runbooks.

| Document | Use when |
| --- | --- |
| [Recovery and operations drills](recovery-and-operations-drills.md) | Planning or recording resilience exercises |
| [Storage pressure recovery plan](storage-pressure-recovery-plan-2026-07-18.md) | Longhorn, NFS, or node storage is under pressure |
| [Change management](change-management.md) | Preparing, applying, verifying, and closing platform changes |
| [Architecture migration plan](../architecture/migration.md) | Migrating the GitOps layout or control plane |
| [Topology migration](../architecture/topology-migration.md) | Moving, renaming, draining, or replacing cluster nodes |

## Operational evidence standard

Every drill or incident record should capture:

- UTC start and end time
- operator and change reference
- commands or dashboards used
- before/after health state
- data-loss assessment
- follow-up issue or explicit “no follow-up” decision

Never paste credentials, tokens, private keys, or unredacted secret values into an incident record.
