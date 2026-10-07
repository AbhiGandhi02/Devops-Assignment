# AWS IAM - Identity and Access Management

**Name:** Abhi Gandhi
**Enrollment Number:** 24bcs10397

IAM is the first AWS service I need to understand before writing any Terraform, because
Terraform itself authenticates as an IAM identity and every resource it creates is allowed or
denied by IAM policies.

## What is IAM

IAM controls **who** (authentication) can do **what** on **which resources** (authorization)
in an AWS account.

- It is a **global** service - not tied to a region.
- It is **free** - there is no charge for users, groups, roles or policies.
- Everything is **denied by default**. A new identity can do nothing until a policy allows it.

| Concept | What it is | Credentials |
|---|---|---|
| **Root user** | The email that created the account; full, unrestricted access | Password (+ should have MFA) |
| **IAM user** | A long-lived identity for one person or application | Password and/or access keys |
| **IAM group** | A collection of users that share policies | None - groups cannot log in |
| **IAM role** | An identity with permissions that is **assumed** temporarily | Temporary credentials from STS |
| **Policy** | A JSON document that grants or denies permissions | - |

## Users

An IAM user has a name, optional console password, and up to two access keys
(`AKIA...` key ID + secret) for the CLI/SDK.

```bash
aws iam create-user --user-name abhi-devops-ci
aws iam create-access-key --user-name abhi-devops-ci
aws sts get-caller-identity           # "who am I" - the first command I run when debugging
```

Today, AWS recommends **not** creating IAM users for humans where possible - use IAM Identity
Center (SSO) instead - and not using long-lived access keys where a role would work.

## Groups

Groups exist only to attach policies to many users at once. A user can be in up to 10
groups; groups cannot be nested and cannot be used as a `Principal` in a policy.

```bash
aws iam create-group --group-name developers
aws iam attach-group-policy --group-name developers \
  --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
aws iam add-user-to-group --group-name developers --user-name abhi-devops-ci
```

## Roles

A role has **no long-term credentials**. Something trusted assumes it and receives
temporary credentials (access key, secret, session token) from **STS** that expire (1 hour
by default for `AssumeRole`).

A role has two policies:

1. **Trust policy** - *who* may assume the role.
2. **Permissions policy** - *what* the role may do once assumed.

Trust policy letting EC2 instances assume a role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Typical role uses: EC2 instance profiles, Lambda execution roles, EKS Pods (IRSA / Pod
Identity), cross-account access, GitHub Actions via OIDC federation.

## Policies

A policy is a JSON document made of statements:

| Element | Meaning |
|---|---|
| `Version` | Always `"2012-10-17"` (the current policy language version) |
| `Effect` | `Allow` or `Deny` |
| `Action` | API operations, e.g. `s3:GetObject`, `ec2:*` |
| `Resource` | ARNs the statement applies to |
| `Condition` | Optional - extra rules such as source IP, MFA, tags, region |
| `Principal` | Only in **resource-based** policies (bucket policies, trust policies) |

### Policy types

| Type | Attached to | Example |
|---|---|---|
| AWS managed | Users, groups, roles | `AmazonS3ReadOnlyAccess`, `AdministratorAccess` |
| Customer managed | Users, groups, roles | My own reusable, versioned policy |
| Inline | One identity only | Embedded, deleted with the identity |
| Resource-based | A resource | S3 bucket policy, KMS key policy, role trust policy |
| Permissions boundary | User or role | Maximum permissions an identity can ever have |
| SCP (Organizations) | Account / OU | Guardrail across whole accounts |

### Least-privilege S3 read-only policy

Read objects from one bucket only - nothing else:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListOnlyThisBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::abhi-devops-artifacts"
    },
    {
      "Sid": "ReadObjectsInThisBucket",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::abhi-devops-artifacts/*"
    }
  ]
}
```

The two resources are deliberately different: `s3:ListBucket` acts on the **bucket** ARN,
while `s3:GetObject` acts on **object** ARNs (`/*`). Mixing them up is the most common reason
an S3 policy "does not work".

### Explicit deny with a condition

Deny all EC2 actions outside `ap-south-1`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "ec2:*",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": { "aws:RequestedRegion": "ap-south-1" }
      }
    }
  ]
}
```

## Permissions evaluation logic

For a request inside one account, AWS evaluates every applicable policy and decides:

```text
1. Is there an explicit Deny in ANY applicable policy?  -> DENY (final, nothing overrides it)
2. Is there an Allow (and no SCP / boundary / session policy blocking it)? -> ALLOW
3. Otherwise                                              -> DENY (implicit deny)
```

| Rule | Meaning |
|---|---|
| **Explicit deny** | Always wins, even over `AdministratorAccess` |
| **Explicit allow** | Needed to do anything |
| **Implicit deny** | The default when nothing matches |

SCPs and permissions boundaries **never grant** permissions - they only set the maximum.
The effective permission is the **intersection** of the identity policy and every
boundary/SCP that applies. For cross-account access, **both** sides must allow it (the
identity policy in account A and the resource policy or role trust in account B).

## Least privilege

Grant only the actions, on only the resources, for only the time needed.

- Start from nothing and add, rather than starting from `*` and removing.
- Scope `Resource` to specific ARNs instead of `"*"`.
- Use `Condition` keys (`aws:SourceIp`, `aws:MultiFactorAuthPresent`, `aws:ResourceTag/...`).
- Use **IAM Access Analyzer** to generate a policy from CloudTrail activity and to find
  resources shared outside the account.
- Review **last accessed** data and remove unused permissions.

## Best practices

| Practice | Why |
|---|---|
| Enable **MFA on root**, lock root away, no root access keys | Root cannot be restricted by IAM policies |
| Use **roles and temporary credentials** instead of access keys | Nothing long-lived to leak |
| Use **IAM Identity Center / federation** for humans | Central SSO, no per-account users |
| Attach policies to **groups or roles**, not individual users | Easier to audit and change |
| Apply **least privilege** | Limits the blast radius of a leaked credential |
| **Rotate** any access keys that must exist; never commit them to Git | Leaked keys are scanned for within minutes |
| Enforce a **password policy** and MFA for console users | Basic account hygiene |
| Use **permissions boundaries / SCPs** as guardrails | Developers can create roles without escalating |
| Turn on **CloudTrail** | Audit log of every API call |

## Common use cases

| Use case | IAM approach |
|---|---|
| Terraform running in CI (GitHub Actions) | OIDC identity provider + role with a trust policy for the repo |
| EC2 app reading from S3 | Instance profile with an S3 read role - no keys on the server |
| Lambda writing to DynamoDB | Lambda execution role scoped to one table ARN |
| A team of developers | Identity Center permission set or a group with a managed policy |
| Access from another AWS account | Cross-account role with a trust policy naming that account |
| Pods on EKS calling AWS APIs | IRSA or EKS Pod Identity mapping a service account to a role |

## Key takeaways

- IAM is global, free and **deny-by-default**.
- **Users and groups** are for long-lived identities; **roles** give temporary credentials
  through STS and are the preferred option for applications and automation.
- A policy is JSON: `Effect`, `Action`, `Resource`, optional `Condition` (and `Principal`
  for resource-based policies).
- Evaluation: **explicit deny > explicit allow > implicit deny**.
- Least privilege, MFA on root and no long-lived keys are the habits that matter most.
