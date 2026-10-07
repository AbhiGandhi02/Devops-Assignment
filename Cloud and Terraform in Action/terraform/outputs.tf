output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "security_group_id" {
  value = aws_security_group.web.id
}

output "ami_used" {
  value = "${data.aws_ami.ubuntu.id} (${data.aws_ami.ubuntu.name})"
}

output "instance_id" {
  value = aws_instance.web.id
}

output "instance_public_ip" {
  value = aws_instance.web.public_ip
}

output "assets_bucket" {
  value = aws_s3_bucket.assets.bucket
}

output "website_url" {
  value = "http://${aws_instance.web.public_ip}"
}
