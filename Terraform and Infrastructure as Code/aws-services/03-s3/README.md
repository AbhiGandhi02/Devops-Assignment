# AWS S3 - Simple Storage Service

**Name:** Abhi Gandhi
**Enrollment Number:** 24bcs10397

S3 is AWS's object storage, and for Terraform specifically it is where the **remote state
file** usually lives. These are my notes on how S3 is organised, priced, protected and used.

## What is S3

S3 stores **objects** (files plus metadata) inside **buckets**, accessed over HTTPS through
an API - not a disk and not a filesystem you mount.

| Property | Value |
|---|---|
| Durability | 99.999999999% (11 nines) - data copied across at least 3 AZs for most classes |
| Availability | 99.99% designed for S3 Standard |
| Capacity | Unlimited total storage |
| Consistency | Strong read-after-write for all PUTs, overwrites and deletes (since Dec 2020) |
| Scope | Bucket is created in **one region**; bucket names are **globally unique** |
| Pricing | Per GB-month stored + requests + data transfer out (+ retrieval for IA/Glacier) |

## Buckets

- Name: 3-63 characters, lowercase letters, digits, hyphens and dots, globally unique
  across **all** AWS accounts (`abhi-devops-artifacts`).
- Region chosen at creation and cannot be changed.
- Flat namespace - there are no real folders; the console just groups by `/` in the key.
- Default soft limit of 10,000 general purpose buckets per account (it used to be 100).

## Objects

An object is identified by its **key** within a bucket:

```text
s3://abhi-devops-artifacts/builds/2026/app-v1.4.2.tar.gz
     |-------- bucket ----| |----------- key ------------|
```

| Part | Meaning |
|---|---|
| Key | Full name / "path" of the object |
| Value | The bytes |
| Metadata | System (`Content-Type`, `Last-Modified`) and user-defined `x-amz-meta-*` |
| Version ID | Present when versioning is enabled |
| Tags | Up to 10 key-value tags, usable in IAM and lifecycle rules |

A single `PUT` can upload up to **5 GB**; anything larger must use **multipart upload**
(recommended from about 100 MB), which `aws s3 cp` does automatically.

## Storage classes

| Class | AZs | Retrieval | Min storage duration | Use case |
|---|---|---|---|---|
| **S3 Standard** | >= 3 | Milliseconds | None | Frequently accessed data, websites, active app data |
| **S3 Intelligent-Tiering** | >= 3 | Milliseconds (archive tiers optional) | None | Unknown or changing access patterns; small monitoring fee, no retrieval fee |
| **S3 Standard-IA** | >= 3 | Milliseconds, per-GB retrieval fee | 30 days | Infrequent but needs fast access - backups, DR copies |
| **S3 One Zone-IA** | 1 | Milliseconds, retrieval fee | 30 days | Re-creatable infrequent data; lost if the AZ is lost |
| **S3 Express One Zone** | 1 | Single-digit ms | None (1 hour) | Very low latency, high request rate (directory buckets) |
| **S3 Glacier Instant Retrieval** | >= 3 | Milliseconds | 90 days | Archive accessed about once a quarter |
| **S3 Glacier Flexible Retrieval** | >= 3 | Minutes to 12 hours (expedited 1-5 min, standard 3-5 h, bulk 5-12 h) | 90 days | Archives, rarely needed backups |
| **S3 Glacier Deep Archive** | >= 3 | Within 12 hours (bulk up to 48 h) | 180 days | Compliance archives kept 7-10 years; cheapest |

IA and Glacier classes also have a minimum billable object size of 128 KB.

## Versioning

Versioning is set per bucket and has three states: **unversioned** (default),
**enabled**, **suspended** - once enabled it can never return to unversioned.

- Every overwrite creates a new **version ID**; old versions are kept.
- A delete does not remove data - it adds a **delete marker**. Deleting the marker restores
  the object.
- Old versions are billed as normal storage, so pair versioning with a lifecycle rule.
- **MFA Delete** can require MFA to permanently delete versions.
- Required for **replication** (CRR / SRR) and essential for a Terraform state bucket.

```bash
aws s3api put-bucket-versioning --bucket abhi-devops-tfstate \
  --versioning-configuration Status=Enabled
aws s3api list-object-versions --bucket abhi-devops-tfstate --prefix envs/dev/
```

## Lifecycle policies

Lifecycle rules automatically **transition** objects to cheaper classes or **expire** them:

```json
{
  "Rules": [
    {
      "ID": "logs-tiering",
      "Filter": { "Prefix": "logs/" },
      "Status": "Enabled",
      "Transitions": [
        { "Days": 30,  "StorageClass": "STANDARD_IA" },
        { "Days": 90,  "StorageClass": "GLACIER" },
        { "Days": 180, "StorageClass": "DEEP_ARCHIVE" }
      ],
      "Expiration": { "Days": 365 },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 30 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
    }
  ]
}
```

```bash
aws s3api put-bucket-lifecycle-configuration --bucket abhi-devops-artifacts \
  --lifecycle-configuration file://lifecycle.json
```

`GLACIER` is the API name for Glacier Flexible Retrieval. `AbortIncompleteMultipartUpload`
cleans up half-finished uploads that are otherwise billed invisibly.

## Encryption

Since January 2023 every new object is encrypted at rest by default with SSE-S3.

| Option | Who manages keys | Notes |
|---|---|---|
| **SSE-S3** | AWS (S3-managed AES-256 keys) | Default, free, nothing to configure |
| **SSE-KMS** | AWS KMS key (AWS managed `aws/s3` or my customer managed key) | Key policy controls access, CloudTrail logs every key use, KMS request costs (reduced with **S3 Bucket Keys**) |
| **DSSE-KMS** | KMS, two layers of encryption | For compliance that requires dual-layer |
| **SSE-C** | I supply the key with every request | S3 does not store the key |
| **Client-side** | I encrypt before upload (e.g. AWS Encryption SDK) | S3 only ever sees ciphertext |

**In transit:** HTTPS. A bucket policy can deny non-TLS requests with
`"Condition": {"Bool": {"aws:SecureTransport": "false"}}`.

```bash
aws s3api put-bucket-encryption --bucket abhi-devops-artifacts \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms","KMSMasterKeyID":"alias/abhi-s3"},"BucketKeyEnabled":true}]}'
```

## Bucket policies

A bucket policy is a **resource-based** IAM policy attached to the bucket, so it has a
`Principal`. This one lets a specific role read objects and denies any request not using
HTTPS:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAppRoleRead",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:role/abhi-devops-app-role" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::abhi-devops-artifacts/*"
    },
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::abhi-devops-artifacts",
        "arn:aws:s3:::abhi-devops-artifacts/*"
      ],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
```

Within one account, access is allowed if **either** the identity policy **or** the bucket
policy allows it (and nothing denies it). ACLs are a legacy mechanism - new buckets default
to **Object Ownership: Bucket owner enforced**, which disables ACLs.

## Block Public Access

Four settings that override any policy or ACL that would make data public:

| Setting | Effect |
|---|---|
| `BlockPublicAcls` | Reject new public ACLs |
| `IgnorePublicAcls` | Ignore any existing public ACLs |
| `BlockPublicPolicy` | Reject bucket policies that grant public access |
| `RestrictPublicBuckets` | Limit access to buckets with public policies to AWS services and the owner account |

All four are **on by default** for new buckets (since April 2023) and can also be set
account-wide. I only turn them off deliberately - for example a static website bucket - and
even then CloudFront with Origin Access Control is the better option.

## Common use cases

- **Terraform remote state** (versioned, encrypted bucket; S3 native locking with
  `use_lockfile = true`, or a DynamoDB table in older setups).
- Static website hosting, usually behind CloudFront.
- Backups, DR copies and long-term archives with lifecycle to Glacier.
- Data lake for Athena, EMR, Glue and Redshift Spectrum.
- Build artifacts, container layers, ML datasets and logs (ALB, CloudTrail, VPC Flow Logs).
- Event-driven processing - S3 event notifications to Lambda, SQS, SNS or EventBridge.

## AWS CLI examples

```bash
aws s3 mb s3://abhi-devops-artifacts --region ap-south-1        # make bucket
aws s3 ls                                                       # list buckets
aws s3 cp app.tar.gz s3://abhi-devops-artifacts/builds/         # upload
aws s3 ls s3://abhi-devops-artifacts/builds/ --recursive         # list objects
aws s3 sync ./site s3://abhi-devops-site --delete                # mirror a folder
aws s3 cp s3://abhi-devops-artifacts/builds/app.tar.gz .         # download
aws s3 presign s3://abhi-devops-artifacts/builds/app.tar.gz --expires-in 3600   # temporary URL

aws s3api put-public-access-block --bucket abhi-devops-artifacts \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-policy --bucket abhi-devops-artifacts --policy file://policy.json

aws s3 rm s3://abhi-devops-artifacts --recursive                # empty bucket
aws s3 rb s3://abhi-devops-artifacts                            # remove bucket
```

`aws s3` is the high-level, file-oriented command; `aws s3api` maps one-to-one onto the S3
API for settings like versioning, lifecycle and policies.

## Key takeaways

- S3 = buckets (globally unique name, one region) holding objects (key + data + metadata),
  with 11 nines durability and strong consistency.
- Pick a **storage class** by access frequency and let **lifecycle rules** move data down
  the tiers automatically.
- **Versioning** protects against overwrites and deletes; deletes just add a delete marker.
- Data is encrypted by default (SSE-S3); use **SSE-KMS** when I need key control and audit.
- Access is controlled by IAM + **bucket policies**, with **Block Public Access** as the
  safety net that is on by default.
