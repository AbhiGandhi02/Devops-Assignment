# AWS DynamoDB and RDS

**Name:** Abhi Gandhi
**Enrollment Number:** 24bcs10397

AWS's two main managed database services, side by side. DynamoDB is the NoSQL key-value
store (and was the classic Terraform state-lock table); RDS runs traditional relational
databases without me managing the servers.

## Part 1: DynamoDB

### What is DynamoDB

DynamoDB is a **fully managed, serverless NoSQL** key-value and document database.

- No servers, no OS, no patching, no version upgrades - I only create **tables**.
- Single-digit millisecond latency at any scale.
- Data is replicated across **3 AZs** in the region automatically.
- No joins and no fixed schema beyond the primary key; access is by key or by index.
- Access is controlled entirely through IAM (no database users or passwords).

### Tables, items and attributes

| DynamoDB | Relational equivalent | Notes |
|---|---|---|
| **Table** | Table | Collection of items |
| **Item** | Row | Max **400 KB** per item |
| **Attribute** | Column | Each item can have different attributes |
| **Primary key** | Primary key | The only attributes that must be defined up front |

Attribute types: scalars (`S` string, `N` number, `B` binary, `BOOL`, `NULL`), documents
(`M` map, `L` list) and sets (`SS`, `NS`, `BS`).

An item from an `Orders` table:

```json
{
  "CustomerId": { "S": "C-1001" },
  "OrderDate":  { "S": "2026-10-07T10:15:00Z" },
  "Total":      { "N": "1499" },
  "Currency":   { "S": "INR" },
  "Items":      { "L": [ { "S": "keyboard" }, { "S": "mouse" } ] }
}
```

### Partition key and sort key

| Primary key type | Made of | Uniqueness |
|---|---|---|
| **Simple** | Partition key only | Partition key must be unique |
| **Composite** | Partition key + sort key | The **combination** must be unique |

- The **partition key** (hash key) is hashed to decide which physical partition stores the
  item. A high-cardinality key (`CustomerId`, `UserId`) spreads load evenly; a low one
  (`Status`) creates a **hot partition**.
- The **sort key** (range key) orders items that share a partition key and enables range
  queries: `begins_with`, `between`, `>`, `<`.
- With `CustomerId` + `OrderDate`, "all orders for C-1001 in October 2026" is one efficient
  `Query` instead of a full-table `Scan`.

### Capacity modes

| | **On-demand** | **Provisioned** |
|---|---|---|
| Billing | Per read/write request | Per hour for RCU/WCU set |
| Planning | None - scales instantly | I set capacity, optionally with **auto scaling** |
| Best for | New, spiky or unpredictable traffic | Steady, predictable traffic (cheaper at scale) |
| Throttling | Rare | If traffic exceeds provisioned capacity |

Units: **1 RCU** = one strongly consistent read per second of up to 4 KB (or two eventually
consistent reads). **1 WCU** = one write per second of up to 1 KB. Transactional reads and
writes cost double.

### Secondary indexes

| | **GSI** (Global) | **LSI** (Local) |
|---|---|---|
| Key | **Any** partition key + optional sort key | **Same** partition key, different sort key |
| When created | Any time | **Only at table creation** |
| Limit (default) | 20 per table | 5 per table |
| Consistency | Eventually consistent only | Eventual or strong |
| Capacity | Its own | Shares the table's |

Example: a GSI on `Status` + `OrderDate` lets me query "all PENDING orders" without scanning.

### Other features worth knowing

- **Streams** - ordered change log of item updates, typically consumed by Lambda.
- **TTL** - automatically deletes items after an epoch-time attribute, at no cost.
- **PITR** - point-in-time restore to any second in the last 35 days; plus on-demand backups.
- **Global Tables** - multi-region, multi-active replication.
- **DAX** - in-memory cache with microsecond reads.
- **Transactions** - ACID across up to 100 items.

### DynamoDB use cases

- Session stores, user profiles, shopping carts.
- Gaming leaderboards, IoT telemetry, ad tech - huge request rates.
- Serverless backends (API Gateway + Lambda + DynamoDB).
- Metadata and idempotency tables; Terraform state locking in older S3 backends
  (`dynamodb_table` with a `LockID` string partition key, now superseded by
  `use_lockfile = true`).

```bash
aws dynamodb create-table --table-name Orders \
  --attribute-definitions AttributeName=CustomerId,AttributeType=S AttributeName=OrderDate,AttributeType=S \
  --key-schema AttributeName=CustomerId,KeyType=HASH AttributeName=OrderDate,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST

aws dynamodb query --table-name Orders \
  --key-condition-expression "CustomerId = :c AND begins_with(OrderDate, :m)" \
  --expression-attribute-values '{":c":{"S":"C-1001"},":m":{"S":"2026-10"}}'
```

## Part 2: RDS

### What is RDS

Amazon **Relational Database Service** runs relational databases for me. AWS handles
provisioning, OS and engine patching, backups, monitoring and failover; I handle schema,
queries, indexes and tuning. There is **no SSH/OS access** to the host (RDS Custom is the
exception).

### Supported engines

| Engine | Notes |
|---|---|
| **Amazon Aurora** (MySQL- and PostgreSQL-compatible) | AWS-built; storage is 6 copies across 3 AZs, auto-growing; up to 15 low-lag replicas; Aurora Serverless v2 |
| **PostgreSQL** | Open source |
| **MySQL** | Open source |
| **MariaDB** | Open source MySQL fork |
| **Oracle** | Bring-your-own-license or license-included |
| **Microsoft SQL Server** | License-included |
| **IBM Db2** | Added in 2023 |

### DB instances and classes

A **DB instance** is one isolated database environment, sized by a **DB instance class**
(same naming idea as EC2, with a `db.` prefix):

| Class family | Type | Example |
|---|---|---|
| `db.t3`, `db.t4g` | Burstable | `db.t4g.micro` - dev / test |
| `db.m6i`, `db.m7g` | General purpose | `db.m7g.large` |
| `db.r6i`, `db.r7g`, `db.x2g` | Memory optimized | `db.r7g.xlarge` - large buffer pools |

Storage is EBS-based (`gp3`, `io1`, `io2`) with optional **storage autoscaling**. Aurora uses
its own cluster storage instead.

### Security

- Runs inside my **VPC** using a **DB subnet group** (private subnets in at least 2 AZs);
  `PubliclyAccessible = false` for production.
- **Security groups** - allow port 5432 / 3306 only from the application's SG.
- **Encryption at rest** with KMS - must be chosen **at creation**; covers storage, backups,
  snapshots and replicas. An unencrypted DB is encrypted by copying a snapshot with
  encryption and restoring it.
- **Encryption in transit** with TLS (can be enforced with engine parameters such as
  `rds.force_ssl`).
- **Authentication** - master password (ideally managed in **Secrets Manager** with
  rotation), or **IAM database authentication** for MySQL / PostgreSQL.

### Backups, snapshots and PITR

| | **Automated backups** | **Manual snapshots** |
|---|---|---|
| Taken by | AWS, daily in the backup window + transaction logs | Me, on demand |
| Retention | 0-35 days (0 disables them) | Until I delete them |
| Deleted with the DB | Yes (unless retained) | No |
| Restore | **Point-in-time** to any second in the retention window (typically within the last ~5 minutes) | To the moment of the snapshot |

A restore always creates a **new DB instance** with a new endpoint - it never overwrites the
existing one. Snapshots can be copied across regions and shared across accounts.

### Multi-AZ

| | **Multi-AZ (instance)** | **Multi-AZ DB cluster** |
|---|---|---|
| Standbys | 1 in another AZ | 2 in two other AZs |
| Replication | **Synchronous** | Semi-synchronous |
| Standby readable? | **No** - for failover only | Yes, via reader endpoint |
| Engines | All | MySQL, PostgreSQL |

On failure (AZ outage, instance failure, or during patching) RDS fails over by flipping the
**DNS endpoint** to the standby, typically in 60-120 seconds for the instance deployment.
The app reconnects to the same hostname. Multi-AZ is for **availability**, not for scaling
reads.

### Read replicas

- **Asynchronous** copies used to **scale reads** (reports, analytics, read-heavy APIs).
- Up to 15 for MySQL, MariaDB and PostgreSQL (fewer for Oracle and SQL Server); Aurora
  supports up to 15 Aurora Replicas.
- Each has its **own endpoint**; the app must send reads there.
- Can be **cross-region** for DR and local reads, and can be **promoted** to a standalone
  writable database.
- Replication lag means reads may be slightly stale.

### RDS use cases

- Web and mobile application backends with relational data.
- E-commerce orders, payments, inventory - anything needing ACID transactions and joins.
- ERP / CRM systems, and lift-and-shift of existing MySQL, PostgreSQL, Oracle or SQL Server.
- Reporting with complex SQL queries (with read replicas).

```bash
aws rds create-db-instance \
  --db-instance-identifier abhi-devops-db \
  --engine postgres --db-instance-class db.t4g.micro \
  --allocated-storage 20 --storage-type gp3 \
  --master-username dbadmin --manage-master-user-password \
  --db-subnet-group-name abhi-db-subnets --vpc-security-group-ids sg-0db \
  --backup-retention-period 7 --multi-az --storage-encrypted --no-publicly-accessible

aws rds create-db-snapshot --db-instance-identifier abhi-devops-db --db-snapshot-identifier abhi-db-before-migration
aws rds create-db-instance-read-replica --db-instance-identifier abhi-devops-db-replica \
  --source-db-instance-identifier abhi-devops-db
```

## When to use which

| Requirement | DynamoDB | RDS / Aurora |
|---|---|---|
| Data model | Key-value / document, flexible attributes | Tables with fixed schema and relationships |
| Queries | By key or index; no joins | Full SQL, joins, aggregations, ad-hoc queries |
| Transactions | Supported, limited (100 items) | Full ACID, any size |
| Scaling | Horizontal, automatic, virtually unlimited | Mostly vertical; read replicas for reads |
| Operations | Serverless, nothing to size (on-demand) | Choose instance class, storage, maintenance windows |
| Latency | Consistent single-digit ms at any scale | Low, but depends on query and instance size |
| Pricing | Per request or provisioned capacity + storage | Per instance-hour + storage + I/O |
| Access control | IAM only | DB users + SGs (+ IAM auth) |
| Good fit | Sessions, carts, IoT, gaming, serverless APIs | Orders/payments, ERP, reporting, existing SQL apps |

My rule of thumb: if I know the access patterns up front and need massive scale, choose
**DynamoDB**; if the data is relational or the queries are not known in advance, choose
**RDS** (or Aurora when I need more performance and availability).

## Key takeaways

- **DynamoDB** is serverless NoSQL: tables of items, a partition key (plus optional sort
  key) for access, on-demand or provisioned capacity, GSIs/LSIs for other access patterns.
- Partition key design decides performance - high cardinality avoids hot partitions.
- **RDS** is managed SQL: MySQL, PostgreSQL, MariaDB, Oracle, SQL Server, Db2 and Aurora on
  DB instance classes inside my VPC.
- **Multi-AZ** = synchronous standby for high availability; **read replicas** =
  asynchronous copies for read scaling.
- Automated backups give point-in-time restore within the retention window (up to 35
  days); manual snapshots last until deleted, and every restore creates a new instance.
