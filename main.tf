## This will use the Amazon Linux 2 AMI
## However, the Amazon Linux 2 AMI has not yet been ECS optimised
## Once that version is out, it will be a better option for ECS
## As it is much lighter weight and has many performance improvements

# data "aws_ami" "ecs_ami" {
#   most_recent = true

#   filter {
#     name   = "owner-alias"
#     values = ["amazon"]
#   }

#   filter {
#     name   = "name"
#     values = ["amzn2-ami-hvm*"]
#   }
# }

data "aws_ami" "ecs_ami" {
  most_recent = true

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn-ami-*-amazon-ecs-optimized"]
  }
}

resource "aws_ecs_cluster" "default" {
  #count = "${var.existing_cluster_name == "" ? 1 : 0}"
  count = "${var.create_cluster == "true" ? 1 : 0}"
  name  = "${var.cluster_label == "" ? module.label.id : var.cluster_label}"
}

locals {
  cluster_name             = "${var.existing_cluster_name == "" ? "${element(split("/", join("",aws_ecs_cluster.default.*.arn)), 1)}" : var.existing_cluster_name }"
  iam_instance_profile_arn = "${var.iam_instance_profile_arn == "" ? aws_iam_instance_profile.instance_profile.arn : ""}"
  ami_id                   = "${var.ami_id == "" ? data.aws_ami.ecs_ami.id : var.ami_id}"
  security_groups          = "${concat(var.security_group_ids, list(aws_security_group.default.id))}"
}

data "aws_region" "default" {}

resource "aws_cloudwatch_log_group" "default" {
  name_prefix = "${module.label.id}"
  tags        = "${module.label.tags}"
}

resource "aws_launch_template" "default" {
  name          = "${module.label.id}-launch-template"
  image_id      = "${local.ami_id}"
  instance_type = "${var.instance_type}"
  key_name      = "${var.key_name}"
  ebs_optimized = "${var.ebs_optimized}"

  instance_market_options {
    market_type = "spot"
  }

  #vpc_security_group_ids = ["${local.security_groups}"]
  #placement_group        = "${var.placement_group}"

  iam_instance_profile {
    arn = "${local.iam_instance_profile_arn}"
  }
  monitoring {
    enabled = "${var.monitoring}"
  }
  tag_specifications {
    resource_type = "instance"
    tags          = "${module.label.tags}"
  }
  tag_specifications {
    resource_type = "volume"
    tags          = "${module.label.tags}"
  }
  ## Move up
  network_interfaces {
    associate_public_ip_address = "${var.associate_public_ip_address}"
    description                 = "${module.label.id}"
    subnet_id                   = "${var.subnet_ids[0]}"
    device_index                = "0"
    security_groups             = ["${local.security_groups}"]
  }

  # // root partition
  # block_device_mappings {
  #   device_name = "/dev/sda1"

  #   ebs {
  #     volume_size = "${var.disk_size_root}"
  #     volume_type = "gp2"
  #   }
  # }
  // docker partition
  block_device_mappings {
    device_name = "/dev/xvdcz"

    ebs {
      volume_size           = "${var.disk_size_docker}"
      volume_type           = "gp2"
      delete_on_termination = "true"
    }
  }
  user_data = "${data.template_cloudinit_config.config.rendered}"
  tags      = "${module.label.tags}"
  lifecycle {
    create_before_destroy = true
  }
}

# resource "aws_spot_fleet_request" "default" {
#   depends_on                          = ["aws_ecs_cluster.default", "null_resource.launch_specification"]
#   iam_fleet_role                      = "${aws_iam_role.taggingrole.arn}"
#   allocation_strategy                 = "${var.allocation_strategy}"
#   target_capacity                     = "${var.target_capacity}"
#   wait_for_fulfillment                = "${var.wait_for_fulfillment}"
#   excess_capacity_termination_policy  = "${var.excess_capacity_termination_policy}"
#   terminate_instances_with_expiration = "${var.terminate_instances_with_expiration}"
#   depends_on                          = ["aws_iam_policy_attachment.spot_request_policy", "aws_iam_policy_attachment.attach"]
#   on_demand_target_capacity           = "${var.on_demand_target_capacity}"

#   launch_template_configs {
#     launch_template_specification {
#       name    = "${aws_launch_template.default.name}"
#       version = "${aws_launch_template.default.latest_version}"
#     }
#   }

#   timeouts {
#     create = "20m"
#   }

#   lifecycle {
#     create_before_destroy = true
#   }
# }

resource "aws_security_group" "default" {
  name_prefix = "${module.label.id}"
  vpc_id      = "${var.vpc_id}"
}

resource "aws_security_group_rule" "allow_outbound" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["${var.outbound_traffic_cidr}"]
  description = "${module.label.id}"

  security_group_id = "${aws_security_group.default.id}"
}

resource "aws_security_group_rule" "ssh_access" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["${var.cidr_range_for_ssh_access}"]
  description = "${module.label.id}"

  security_group_id = "${aws_security_group.default.id}"
}
