# AWS VPC - Virtual Private Cloud

**Name:** Abhi Gandhi
**Enrollment Number:** 24bcs10397

The VPC is the network every EC2 instance, RDS database and EKS node sits in. It is usually
the first module in a Terraform project, so I wanted to understand each building block and
how a packet actually gets in and out.

## What is a VPC

A VPC is a **logically isolated private network** inside one AWS region. I choose its IP
range, split it into subnets, and control routing and firewalls.

- A VPC spans **all AZs** of a region; each **subnet** lives in exactly **one AZ**.
- Every region has a **default VPC** (`172.31.0.0/16`) with public subnets, for quick tests.
- By default, nothing inside a new VPC can reach the internet - I have to add the pieces.

| Component | Job |
|---|---|
| CIDR block | The VPC's private IP range |
| Subnet | A slice of that range in one AZ |
| Route table | Where traffic from a subnet goes |
| Internet Gateway (IGW) | Two-way connection between the VPC and the internet |
| NAT Gateway | Outbound-only internet for private subnets |
| Security Group | Stateful firewall on each ENI / instance |
| Network ACL | Stateless firewall on each subnet |

## CIDR

CIDR notation `a.b.c.d/n` means "the first `n` bits are the network, the rest are hosts", so
a block holds `2^(32-n)` addresses. A VPC's IPv4 block must be between **/16** (65,536
addresses) and **/28** (16 addresses), and should use RFC 1918 private ranges
(`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`).

### Worked example: 10.0.0.0/16 into /24 subnets

```text
VPC        10.0.0.0/16   -> 2^(32-16) = 65,536 addresses  (10.0.0.0 - 10.0.255.255)
Subnet     /24           -> 2^(32-24) = 256 addresses each
How many   2^(24-16)     = 256 possible /24 subnets (10.0.0.0/24 ... 10.0.255.0/24)
```

| Subnet | CIDR | AZ | Type | Range |
|---|---|---|---|---|
| public-a | `10.0.1.0/24` | ap-south-1a | Public | 10.0.1.0 - 10.0.1.255 |
| public-b | `10.0.2.0/24` | ap-south-1b | Public | 10.0.2.0 - 10.0.2.255 |
| private-a | `10.0.11.0/24` | ap-south-1a | Private | 10.0.11.0 - 10.0.11.255 |
| private-b | `10.0.12.0/24` | ap-south-1b | Private | 10.0.12.0 - 10.0.12.255 |

### AWS reserves 5 IPs in every subnet

For `10.0.1.0/24`:

| Address | Reserved for |
|---|---|
| `10.0.1.0` | Network address |
| `10.0.1.1` | VPC router |
| `10.0.1.2` | Amazon DNS server (VPC base + 2) |
| `10.0.1.3` | Reserved for future use |
| `10.0.1.255` | Network broadcast (AWS does not support broadcast, but reserves it) |

So a /24 gives **256 - 5 = 251 usable** addresses, and the smallest subnet (/28) gives only
**11**. This matters for EKS, where every Pod takes a VPC IP.

## Subnets

A subnet is a CIDR range in one AZ. "Public" and "private" are **not settings** - they
depend only on the route table associated with the subnet.

- Spread subnets across at least **2 AZs** for high availability.
- `MapPublicIpOnLaunch` makes instances in a public subnet get a public IP automatically.

## Route tables

Each subnet is associated with exactly one route table (the **main** route table if none is
set). The most specific matching route wins (longest prefix match).

Public route table:

| Destination | Target |
|---|---|
| `10.0.0.0/16` | `local` (always present, cannot be removed) |
| `0.0.0.0/0` | `igw-0abc...` (Internet Gateway) |

Private route table:

| Destination | Target |
|---|---|
| `10.0.0.0/16` | `local` |
| `0.0.0.0/0` | `nat-0def...` (NAT Gateway) |

## Internet Gateway

- Horizontally scaled, redundant and highly available - no bandwidth limit to manage.
- One IGW per VPC; free (data transfer still billed).
- Performs **1:1 NAT** between an instance's private IP and its public / Elastic IP.
- An instance is reachable from the internet only if: it has a **public IP**, its subnet
  routes `0.0.0.0/0` to the **IGW**, and the **SG and NACL** allow the traffic.

## NAT Gateway

Lets instances in **private** subnets start **outbound** connections (OS updates, calling
external APIs, pulling images) while staying unreachable from the internet.

- Created in a **public** subnet with an **Elastic IP**; the private route table points
  `0.0.0.0/0` at it.
- Managed and zonal - for HA create **one per AZ**, each used by that AZ's private subnets.
- Charged per hour **and** per GB processed - often a surprise on the bill.
- Older alternative: a self-managed **NAT instance**. For IPv6, use an **Egress-only IGW**.
- Traffic to S3 / DynamoDB can skip the NAT entirely using free **gateway VPC endpoints**.

## Security Groups vs Network ACLs

| | **Security Group** | **Network ACL** |
|---|---|---|
| Applies to | Instance / ENI | Subnet (all instances in it) |
| State | **Stateful** - return traffic automatically allowed | **Stateless** - return traffic must be allowed explicitly |
| Rules | **Allow only** | **Allow and Deny** |
| Evaluation | All rules evaluated together | In **rule-number order**, lowest first; first match wins |
| Default | New SG: deny all inbound, allow all outbound | Default NACL: allow all; a new custom NACL: deny all |
| Sources | CIDR, prefix list, or another SG | CIDR only |
| Ephemeral ports | Not needed | Must allow return ports (`1024-65535`) |
| Typical use | Main, fine-grained firewall | Coarse subnet guardrail, blocking a specific IP range |

Because NACLs are stateless, allowing inbound port 443 is not enough - the outbound NACL
must also allow the response to the client's ephemeral port.

## Public vs private subnet

| | **Public subnet** | **Private subnet** |
|---|---|---|
| Default route `0.0.0.0/0` | Internet Gateway | NAT Gateway (or none at all) |
| Instances have public IPs | Usually | No |
| Reachable from internet | Yes (if SG allows) | No |
| Can reach internet | Yes, directly | Outbound only through NAT |
| Put here | ALB / NLB, NAT Gateway, bastion host | App servers, RDS, EKS nodes, caches |

## Architecture diagram

```text
                                 Internet
                                    |
                           +--------+--------+
                           | Internet Gateway|
                           +--------+--------+
 VPC 10.0.0.0/16 (ap-south-1)       |
 +----------------------------------+-----------------------------------+
 |        AZ ap-south-1a                 AZ ap-south-1b                 |
 |  +---------------------------+       +---------------------------+   |
 |  | Public  10.0.1.0/24       |       | Public  10.0.2.0/24       |   |
 |  | [ALB node]  [NAT GW-a]    | <---> | [ALB node]  [NAT GW-b]    |   |
 |  +---------------------------+       +---------------------------+   |
 |                |                                   |                 |
 |                v                                   v                 |
 |  +---------------------------+       +---------------------------+   |
 |  | Private 10.0.11.0/24      |       | Private 10.0.12.0/24      |   |
 |  | [EC2 app]   [RDS primary] |       | [EC2 app]   [RDS standby] |   |
 |  +---------------------------+       +---------------------------+   |
 +----------------------------------------------------------------------+

 Private route tables: 0.0.0.0/0 -> NAT GW in the same AZ
 Public route table:   0.0.0.0/0 -> Internet Gateway
 Inbound:  user -> IGW -> ALB (public) -> EC2 app (private)
 Outbound: EC2 app (private) -> NAT GW (public) -> IGW -> internet
```

## AWS CLI sketch

```bash
aws ec2 create-vpc --cidr-block 10.0.0.0/16
aws ec2 create-subnet --vpc-id vpc-0123 --cidr-block 10.0.1.0/24 --availability-zone ap-south-1a
aws ec2 create-internet-gateway
aws ec2 attach-internet-gateway --internet-gateway-id igw-0abc --vpc-id vpc-0123
aws ec2 create-route-table --vpc-id vpc-0123
aws ec2 create-route --route-table-id rtb-0pub --destination-cidr-block 0.0.0.0/0 --gateway-id igw-0abc
aws ec2 associate-route-table --route-table-id rtb-0pub --subnet-id subnet-0puba
aws ec2 allocate-address --domain vpc
aws ec2 create-nat-gateway --subnet-id subnet-0puba --allocation-id eipalloc-0abc
```

## Key takeaways

- A VPC is a regional private network; subnets are AZ-scoped slices of its CIDR.
- `10.0.0.0/16` holds 65,536 addresses and 256 `/24` subnets of 251 usable IPs each,
  because AWS reserves 5 per subnet.
- A subnet is **public** only because its route table sends `0.0.0.0/0` to an **IGW**;
  private subnets use a **NAT Gateway** for outbound-only access.
- **Security groups** are stateful, allow-only, per instance; **NACLs** are stateless,
  allow/deny, ordered, per subnet.
- Production pattern: public subnets for load balancers and NAT, private subnets for apps
  and databases, repeated across at least two AZs.
