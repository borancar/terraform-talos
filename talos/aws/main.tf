variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "talos_version" {
  type    = string
  default = "v0.10.3"
}

data "aws_ami" "talos_ami" {
  owners      = ["540036508848"] # Talos ID
  most_recent = true

  filter {
    name   = "name"
    values = ["talos-${var.talos_version}-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "ena-support"
    values = [true]
  }
}

resource "aws_security_group" "talos_k8s" {
  name   = "${var.cluster_name}-sg"
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "all_self" {
  security_group_id = aws_security_group.talos_k8s.id

  type      = "ingress"
  from_port = 0
  to_port   = 0
  protocol  = "all"
  self      = true
}

resource "aws_security_group_rule" "k8s_api" {
  security_group_id = aws_security_group.talos_k8s.id

  type        = "ingress"
  from_port   = 6443
  to_port     = 6443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "talos_api" {
  security_group_id = aws_security_group.talos_k8s.id

  type        = "ingress"
  from_port   = 50000
  to_port     = 50001
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "outbound" {
  security_group_id = aws_security_group.talos_k8s.id

  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "all"
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_lb" "talos_nlb" {
  name               = "${var.cluster_name}-k8s-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.subnet_ids
}

resource "talos_cluster_config" "talos_config" {
  cluster_name = var.cluster_name
  endpoint     = "https://${aws_lb.talos_nlb.dns_name}:6443"
}

resource "aws_launch_template" "talos_bootstrap" {
  name     = "${var.cluster_name}-bootstrap"
  image_id = data.aws_ami.talos_ami.id

  instance_type = "t3.small"

  network_interfaces {
    subnet_id                   = var.subnet_ids[0]
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups = [
      aws_security_group.talos_k8s.id,
    ]
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name    = "talos-bootstrap"
      Cluster = var.cluster_name
    }
  }

  user_data = base64encode(talos_cluster_config.talos_config.bootstrap_user_data)
}

resource "aws_autoscaling_group" "talos_bootstrap" {
  name     = "${var.cluster_name}-bootstrap"
  max_size = 1
  min_size = 1

  target_group_arns = [
    aws_lb_target_group.talos_apiserver.id
  ]

  launch_template {
    id      = aws_launch_template.talos_bootstrap.id
    version = "$Latest"
  }
}

resource "aws_lb_target_group" "talos_apiserver" {
  name     = "${var.cluster_name}-k8s-apiserver"
  port     = 6443
  protocol = "TCP"
  vpc_id   = var.vpc_id
}

resource "aws_lb_listener" "talos_apiserver" {
  load_balancer_arn = aws_lb.talos_nlb.arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.talos_apiserver.arn
  }
}

resource "aws_launch_template" "talos_control" {
  name          = "${var.cluster_name}-control"
  image_id      = data.aws_ami.talos_ami.id
  instance_type = "t3.small"

  network_interfaces {
    subnet_id                   = var.subnet_ids[0]
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups = [
      aws_security_group.talos_k8s.id,
    ]
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name    = "talos-control"
      Cluster = var.cluster_name
    }
  }

  user_data = base64encode(talos_cluster_config.talos_config.controlplane_user_data)
}

resource "aws_autoscaling_group" "talos_control" {
  name     = "${var.cluster_name}-control"
  max_size = 2
  min_size = 2

  vpc_zone_identifier = slice(var.subnet_ids, 1, length(var.subnet_ids))

  target_group_arns = [
    aws_lb_target_group.talos_apiserver.id
  ]

  launch_template {
    id      = aws_launch_template.talos_control.id
    version = "$Latest"
  }
}

resource "aws_launch_template" "talos_worker" {
  name          = "${var.cluster_name}-worker"
  image_id      = data.aws_ami.talos_ami.id
  instance_type = "t3.small"

  network_interfaces {
    subnet_id                   = var.subnet_ids[0]
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups = [
      aws_security_group.talos_k8s.id,
    ]
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name    = "talos-worker"
      Cluster = var.cluster_name
    }
  }

  user_data = base64encode(talos_cluster_config.talos_config.join_user_data)
}

resource "aws_autoscaling_group" "talos_worker" {
  name     = "${var.cluster_name}-worker"
  max_size = 3
  min_size = 3

  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.talos_worker.id
    version = "$Latest"
  }
}

output "talos_ami" {
  value = data.aws_ami.talos_ami.id
}

output "talos_ami_name" {
  value = data.aws_ami.talos_ami.name
}

output "nlb_arn" {
  value = aws_lb.talos_nlb.arn
}

output "nlb_dns_name" {
  value = aws_lb.talos_nlb.dns_name
}

output "talos_config" {
  value = talos_cluster_config.talos_config.talos_config
}
