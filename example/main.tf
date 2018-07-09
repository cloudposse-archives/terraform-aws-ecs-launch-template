data "aws_region" "default" {}

data "aws_subnet" "default" {
  id = "${data.aws_subnet_ids.all.ids[0]}"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = "${data.aws_vpc.default.id}"
}

provider "aws" {
  region = "us-east-1"
}

module "label" {
  source    = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.1.3"
  namespace = "cp"
  stage     = "dev"
  name      = "app"

  tags = {
    ManagedBy = "Terraform"
  }
}

module "ssh_key_pair" {
  source                = "git::https://github.com/cloudposse/terraform-aws-key-pair.git?ref=master"
  namespace             = "${module.label.namespace}"
  stage                 = "${module.label.stage}"
  name                  = "${module.label.name}"
  tags                  = "${module.label.tags}"
  ssh_public_key_path   = "${path.module}"
  generate_ssh_key      = "true"
  private_key_extension = ".pem"
  public_key_extension  = ".pub"
  chmod_command         = "chmod 600 %v"
}

resource "aws_ecs_cluster" "default" {
  name = "${module.label.id}"
}

locals {
  cluster_name = "${element(split("/", aws_ecs_cluster.default.arn), 1)}"
}

module "spot_launch_template" {
  source                = "../"
  namespace             = "${module.label.namespace}"
  stage                 = "${module.label.stage}"
  name                  = "${module.label.name}"
  tags                  = "${module.label.tags}"
  key_name              = "${module.ssh_key_pair.key_name}"
  existing_cluster_name = "${local.cluster_name}"

  create_cluster = "false"
  vpc_id         = "${data.aws_vpc.default.id}"
  subnet_ids     = ["${data.aws_subnet_ids.all.ids}"]
}

data "aws_availability_zones" "available" {}

resource "aws_autoscaling_group" "default" {
  availability_zones        = ["${data.aws_availability_zones.available.names}"]
  name_prefix               = "${module.spot_launch_template.launch_template_name}"
  desired_capacity          = 1
  max_size                  = 1
  force_delete              = true
  health_check_grace_period = "300"
  health_check_type         = "EC2"
  min_size                  = 1
  vpc_zone_identifier       = ["${data.aws_subnet_ids.all.ids}"]

  launch_template = {
    id      = "${module.spot_launch_template.launch_template_id}"
    version = "$$Latest"
  }

  lifecycle {
    create_before_destroy = true
  }
}

output "cluster_name" {
  value = "${aws_ecs_cluster.default.name}"
}

# output "launch_specification" {
#   value = "${module.fleet.launch_specification}"
# }
output "user_data" {
  value = "${module.spot_launch_template.user_data}"
}
