data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = var.ami_owners
  filter {
    name   = "name"
    values = [var.ami_name_pattern]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name

  # boot script installs nginx and pulls index.html from the private bucket using the instance role
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    bucket = aws_s3_bucket.assets.bucket
    key    = aws_s3_object.index.key
    region = var.aws_region
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  # explicit dependency: the route to the internet must exist before boot, or apt-get fails
  depends_on = [aws_route_table_association.public]

  tags = { Name = "${var.project}-web-1" }
}
