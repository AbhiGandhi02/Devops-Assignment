project = "orbit-web"
owner   = "Abhi Gandhi"

aws_region          = "ap-south-1"
vpc_cidr            = "10.20.0.0/16"
public_subnet_cidr  = "10.20.1.0/24"
private_subnet_cidr = "10.20.2.0/24"
ssh_cidr            = "203.0.113.10/32" # replace with your own IP/32

# LocalStack run. For real AWS: delete everything below (defaults = Canonical Ubuntu 24.04 on t3.micro).
use_localstack   = true
ami_owners       = ["amazon"]
ami_name_pattern = "ubuntu/images/hvm-ssd/ubuntu-*"
# t3 (burstable) instances make the AWS provider poll DescribeInstanceCreditSpecifications,
# which LocalStack does not implement, so apply never finishes. Real AWS default stays t3.micro.
instance_type = "m5.large"
