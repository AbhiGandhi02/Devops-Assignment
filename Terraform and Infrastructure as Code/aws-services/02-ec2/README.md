# AWS EC2 - Elastic Compute Cloud

**Name:** Abhi Gandhi
**Enrollment Number:** 24bcs10397

EC2 is the basic "rent a virtual machine" service, and the resource I see in almost every
Terraform tutorial (`aws_instance`). These are my notes on every piece that goes into
launching one.

## What is EC2

EC2 provides resizable virtual servers (**instances**) in the cloud. I choose the OS image,
CPU/memory size, storage, network and firewall rules, and pay only while it runs.

| Pricing model | How it works | Good for |
|---|---|---|
| **On-Demand** | Pay per second (Linux, 60s minimum), no commitment | Dev, short or unpredictable workloads |
| **Savings Plans / Reserved Instances** | 1 or 3 year commitment, up to ~72% off | Steady production load |
| **Spot** | Spare capacity, up to ~90% off, can be reclaimed with a 2-minute notice | Batch jobs, CI runners, fault-tolerant work |
| **Dedicated Hosts / Instances** | Physical server for me alone | Licensing, compliance |

An instance always lives in **one Availability Zone**, inside a subnet of a VPC.

## AMI - Amazon Machine Image

An AMI is the template an instance boots from: root volume snapshot, architecture
(`x86_64` or `arm64`), virtualization type and launch permissions.

- **Regional** - an AMI ID like `ami-0abcd1234ef567890` exists in one region only; copy it to
  use it elsewhere.
- Sources: AWS-provided (Amazon Linux 2023, Ubuntu, Windows), AWS Marketplace, community, or
  my own (`aws ec2 create-image`), typically baked with Packer.
- The architecture of the AMI must match the instance type (an `arm64` AMI needs a Graviton
  type).

```bash
# Latest Amazon Linux 2023 AMI ID via the public SSM parameter
aws ssm get-parameter --region ap-south-1 \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text
```

## Instance types

Names follow **family + generation + attributes . size**:

```text
 m   7   g   d  . 2xlarge
 |   |   |   |      |
 |   |   |   |      +-- size: nano, micro, small, medium, large, xlarge, 2xlarge ...
 |   |   |   +--------- d = local NVMe instance storage
 |   |   +------------- g = AWS Graviton (ARM) processor
 |   +----------------- 7 = generation
 +--------------------- m = family (general purpose)
```

| Example | Read as |
|---|---|
| `t3.micro` | Burstable, 3rd gen, Intel - 2 vCPU, 1 GiB (Free Tier eligible in many regions) |
| `m7g.large` | General purpose, 7th gen, Graviton - 2 vCPU, 8 GiB |
| `c7i.xlarge` | Compute optimized, 7th gen, Intel - 4 vCPU, 8 GiB |
| `r6a.2xlarge` | Memory optimized, 6th gen, AMD - 8 vCPU, 64 GiB |

Other attribute letters: `a` = AMD, `i` = Intel, `n` = enhanced networking, `e` = extra
memory/storage.

| Family | Optimized for | Examples |
|---|---|---|
| `t` | Burstable general purpose (CPU credits) | `t3`, `t4g` |
| `m` | Balanced general purpose | `m6i`, `m7g` |
| `c` | Compute | `c6i`, `c7g` |
| `r`, `x`, `z` | Memory | `r6a`, `x2idn` |
| `i`, `d`, `h` | Storage (high local I/O) | `i4i`, `d3` |
| `p`, `g`, `trn`, `inf` | Accelerated (GPU / ML chips) | `p5`, `g5`, `trn1`, `inf2` |

## Key pairs

A key pair is used for **SSH** to Linux instances (and to decrypt the Windows admin
password). AWS stores the **public** key and injects it into `~/.ssh/authorized_keys` at
first boot; I download the **private** key once and it cannot be retrieved again.

```bash
aws ec2 create-key-pair --key-name abhi-devops-key --key-type ed25519 \
  --query KeyMaterial --output text > abhi-devops-key.pem
chmod 400 abhi-devops-key.pem
ssh -i abhi-devops-key.pem ec2-user@<public-ip>      # ubuntu@ for Ubuntu AMIs
```

**EC2 Instance Connect** and **SSM Session Manager** are alternatives that avoid managing
long-lived keys (Session Manager also needs no inbound port 22).

## Security groups

A security group is a **stateful virtual firewall** attached to an instance's network
interface (ENI).

- **Allow rules only** - there is no deny rule.
- **Stateful** - if inbound traffic is allowed, the reply is automatically allowed out.
- Default: all inbound **denied**, all outbound **allowed**.
- A source can be a CIDR or **another security group** (e.g. "allow 5432 only from the app
  SG").

| Type | Protocol | Port | Source | Purpose |
|---|---|---|---|---|
| SSH | TCP | 22 | `203.0.113.10/32` (my IP only) | Admin access |
| HTTP | TCP | 80 | `0.0.0.0/0` | Public web |
| HTTPS | TCP | 443 | `0.0.0.0/0` | Public web |

```bash
aws ec2 create-security-group --group-name abhi-web-sg --description "web" --vpc-id vpc-0123
aws ec2 authorize-security-group-ingress --group-id sg-0123 --protocol tcp --port 22 --cidr 203.0.113.10/32
```

## EBS - Elastic Block Store

EBS volumes are **network-attached block disks** for an instance.

- Lives in **one AZ** - can only attach to instances in the same AZ.
- **Persists independently** of the instance (the root volume is deleted on termination by
  default, controlled by `DeleteOnTermination`).
- **Snapshots** are incremental, stored in S3 behind the scenes, and can be copied across
  regions or used to create AMIs.
- Can be encrypted with KMS, resized and changed type online.

| Type | Kind | Use |
|---|---|---|
| `gp3` | General purpose SSD (default) | Boot volumes, most workloads; baseline 3,000 IOPS, tunable |
| `gp2` | Older general purpose SSD | IOPS tied to size |
| `io2` / `io1` | Provisioned IOPS SSD | Databases needing guaranteed IOPS; io2 supports Multi-Attach |
| `st1` | Throughput optimized HDD | Big data, logs |
| `sc1` | Cold HDD | Infrequent access, lowest cost |

**Instance store** is different: physically attached NVMe, very fast, but data is **lost**
when the instance stops or terminates.

## Public vs private IP, and Elastic IP

| | **Private IP** | **Public IP** (auto-assigned) | **Elastic IP** |
|---|---|---|---|
| Comes from | Subnet CIDR (e.g. `10.0.1.25`) | AWS pool | Allocated to my account |
| Reachable from | Inside the VPC (and peered / VPN networks) | Internet | Internet |
| On stop / start | **Kept** | **Released - a new one is assigned** | **Kept** |
| Cost | Free | Charged (all public IPv4 is billed since Feb 2024) | Charged, including while unattached |

The instance's OS only ever sees its **private** IP; the Internet Gateway does 1:1 NAT
between the public and private address. An **Elastic IP** is a static public IPv4 I can
remap to another instance instantly - useful when a fixed address is required, though a load
balancer or DNS name is usually a better design.

## Instance lifecycle

```text
          launch
            |
            v
        [pending] ----> [running] ----reboot----> [running]
                          |    |
                   stop   |    | terminate
                          v    v
                   [stopping] [shutting-down] --> [terminated]
                          |
                          v
                      [stopped] ---start---> [pending]
```

| State | Billed for compute? | Notes |
|---|---|---|
| `pending` | No | Booting |
| `running` | **Yes** | |
| `stopping` / `stopped` | No (EBS still billed) | Root EBS kept; may move to new host on start; public IP lost |
| `shutting-down` / `terminated` | No | Permanent. Root volume deleted by default; visible for ~1 hour then gone |
| **Hibernate** | No while hibernated | RAM is saved to the encrypted EBS root volume; on start the processes resume. Must be enabled at launch |
| **Reboot** | Yes | Same host, keeps IPs and instance store data |

Termination protection (`DisableApiTermination`) guards against accidental deletes.

## Common use cases

- Web and application servers behind an Application Load Balancer, with an **Auto Scaling
  Group** keeping the right number of instances.
- Self-managed databases or software that needs OS-level control.
- Bastion / jump hosts for private subnets.
- CI/CD build agents (often Spot).
- GPU training and inference (`p`, `g` families).
- EKS / self-managed Kubernetes worker nodes.

## AWS CLI examples

```bash
# Launch one t3.micro
aws ec2 run-instances \
  --image-id ami-0abcd1234ef567890 \
  --instance-type t3.micro \
  --key-name abhi-devops-key \
  --security-group-ids sg-0123 \
  --subnet-id subnet-0abc \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=abhi-devops-web}]'

# List running instances with their IPs
aws ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,PrivateIpAddress,PublicIpAddress]' \
  --output table

aws ec2 stop-instances      --instance-ids i-0123456789abcdef0
aws ec2 start-instances     --instance-ids i-0123456789abcdef0
aws ec2 terminate-instances --instance-ids i-0123456789abcdef0

# Elastic IP
aws ec2 allocate-address --domain vpc
aws ec2 associate-address --instance-id i-0123456789abcdef0 --allocation-id eipalloc-0abc
```

## Key takeaways

- An instance = **AMI** (what to boot) + **instance type** (how big) + **key pair** (how to
  log in) + **security group** (who can reach it) + **EBS** (disk) + **subnet** (where).
- Instance type names decode as family, generation, attributes and size - `m7g.large` is a
  7th-gen Graviton general-purpose instance.
- Security groups are stateful and allow-only.
- EBS persists and is AZ-bound; instance store is fast but ephemeral.
- Stopping keeps the private IP but loses the auto-assigned public IP; use an Elastic IP or
  a load balancer for a stable address.
