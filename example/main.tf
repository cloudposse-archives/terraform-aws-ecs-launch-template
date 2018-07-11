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

variable "stage" {
  default = "staging"
}

variable "namespace" {
  default = "cp"
}

variable "attributes" {
  type    = "list"
  default = []
}

variable "name" {
  default = "app"
}

variable "network_mode" {
  default = "bridge"
}

variable "alb_listen_port" {
  default = "80"
}

variable "container_port" {
  default = "80"
}

variable "container_protocol" {
  default = "HTTP"
}

variable "health_check_path" {
  default = "/"
}

variable "container_cpu" {
  default = "256"
}

variable "container_memory" {
  default = "512"
}

variable "container_memoryreservation" {
  default = "64"
}

variable "container_image" {
  default = "bitnami/apache:latest"
}

variable "deployment_maximum_percent" {
  default = "200"
}

variable "deployment_minimum_healthy_percent" {
  default = "50"
}

variable "max_containers" {
  default = 20
}

variable "min_containers" {
  default = 2
}

variable "desired_containers" {
  default = 5
}

variable "desired_servers" {
  default = 2
}

variable "max_servers" {
  default = 4
}

variable "log_retention_in_days" {
  default = "365"
}

variable "deregistration_delay" {
  description = "This allows the graceful termination of containers before removing them from an instance. This can be up to 1 min 50 seconds safely. In seconds."
  default     = "110"
}

variable "tags" {
  default = {
    ManagedBy = "Terraform"
  }
}

variable "requires_compatibilities" {
  default = ["EC2"]
}

module "label" {
  source    = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.1.3"
  namespace = "${var.namespace}"
  stage     = "${var.stage}"
  name      = "${var.name}"

  tags = "${var.tags}"
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
  cluster_name = "${basename(aws_ecs_cluster.default.arn)}"
}

module "spot_launch_template" {
  source                 = "../"
  namespace              = "${module.label.namespace}"
  stage                  = "${module.label.stage}"
  name                   = "${module.label.name}"
  tags                   = "${module.label.tags}"
  key_name               = "${module.ssh_key_pair.key_name}"
  existing_cluster_name  = "${local.cluster_name}"
  autoscaling_group_name = "${aws_autoscaling_group.default.name}"
  create_cluster         = "false"
  vpc_id                 = "${data.aws_vpc.default.id}"
  subnet_ids             = ["${data.aws_subnet_ids.all.ids}"]
}

data "aws_availability_zones" "available" {}

resource "aws_autoscaling_group" "default" {
  availability_zones        = ["${data.aws_availability_zones.available.names}"]
  name_prefix               = "${module.spot_launch_template.launch_template_name}"
  desired_capacity          = "${var.desired_servers}"
  max_size                  = "${var.max_servers}"
  force_delete              = true
  health_check_grace_period = "300"
  health_check_type         = "EC2"
  min_size                  = 1
  termination_policies      = ["OldestInstance"]
  vpc_zone_identifier       = ["${data.aws_subnet_ids.all.ids}"]

  launch_template = {
    id      = "${module.spot_launch_template.launch_template_id}"
    version = "$$Latest"
  }

  # lifecycle {
  #   create_before_destroy = true
  # }
}

output "cluster_name" {
  value = "${aws_ecs_cluster.default.name}"
}

module "service_label" {
  source = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.1.3"

  namespace = "${var.namespace}"
  stage     = "${var.stage}"
  name      = "service"
  tags      = "${var.tags}"
}

module "task_label" {
  source = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.1.3"

  namespace = "${var.namespace}"
  stage     = "${var.stage}"
  name      = "task"
  tags      = "${var.tags}"
}

## With ALB
resource "aws_ecs_service" "default" {
  name                               = "${module.service_label.id}"
  cluster                            = "${aws_ecs_cluster.default.id}"
  task_definition                    = "${aws_ecs_task_definition.task.family}:${aws_ecs_task_definition.task.revision}" //"${data.aws_ecs_task_definition.task.family}:${max("${aws_ecs_task_definition.task.revision}", "${data.aws_ecs_task_definition.task.revision}")}"
  desired_count                      = "${var.desired_containers}"
  deployment_maximum_percent         = "${var.deployment_maximum_percent}"
  deployment_minimum_healthy_percent = "${var.deployment_minimum_healthy_percent}"
  launch_type                        = "EC2"

  load_balancer = [{
    target_group_arn = "${aws_alb_target_group.main.id}"
    container_name   = "${module.task_label.id}"
    container_port   = "${var.container_port}"
  }]

  ordered_placement_strategy {
    field = "attribute:ecs.availability-zone"
    type  = "spread"
  }

  ordered_placement_strategy {
    field = "instanceId"
    type  = "spread"
  }

  ordered_placement_strategy {
    field = "memory"
    type  = "binpack"
  }

  lifecycle {
    #create_before_destroy = true    #ignore_changes = ["desired_count"]
  }

  # service_registries {
  #   registry_arn = "${aws_service_discovery_service.service.arn}"
  # }
  depends_on = [
    "aws_alb_listener.front_end",
  ]
}

data "aws_iam_role" "ecs_service_autoscaling" {
  name = "AWSServiceRoleForApplicationAutoScaling_ECSService"
}

resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = "${var.max_containers}"
  min_capacity       = "${var.min_containers}"
  resource_id        = "service/${local.cluster_name}/${aws_ecs_service.default.name}"
  role_arn           = "${data.aws_iam_role.ecs_service_autoscaling.arn}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_policy_scale_down" {
  name               = "scale-down-${module.service_label.id}"
  policy_type        = "StepScaling"
  resource_id        = "service/${local.cluster_name}/${aws_ecs_service.default.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }

  depends_on = ["aws_appautoscaling_target.ecs_target"]
}

resource "aws_appautoscaling_policy" "ecs_policy_scale_up" {
  name               = "scale-up-${module.service_label.id}"
  policy_type        = "StepScaling"
  resource_id        = "service/${local.cluster_name}/${aws_ecs_service.default.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }

  depends_on = ["aws_appautoscaling_target.ecs_target"]
}

### ECS AutoScaling Alarm
resource "aws_cloudwatch_metric_alarm" "service_high" {
  alarm_name          = "${module.service_label.id}-CPU-Utilization-High-30"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "30"

  dimensions {
    ClusterName = "${local.cluster_name}"
    ServiceName = "${aws_ecs_service.default.name}"
  }

  alarm_actions = ["${aws_appautoscaling_policy.ecs_policy_scale_up.arn}"]
}

resource "aws_cloudwatch_metric_alarm" "service_low" {
  alarm_name          = "${module.service_label.id}-CPU-Utilization-Low-5"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "5"

  dimensions {
    ClusterName = "${local.cluster_name}"
    ServiceName = "${aws_ecs_service.default.name}"
  }

  alarm_actions = ["${aws_appautoscaling_policy.ecs_policy_scale_down.arn}"]
}

resource "aws_cloudwatch_log_group" "main" {
  name              = "${module.service_label.id}"
  retention_in_days = "${var.log_retention_in_days}"
  tags              = "${module.service_label.tags}"
}

resource "aws_ecs_task_definition" "task" {
  family                   = "${module.task_label.id}"
  network_mode             = "${var.network_mode}"
  requires_compatibilities = ["${var.requires_compatibilities}"]
  execution_role_arn       = "${aws_iam_role.task_role.arn}"
  cpu                      = "${var.container_cpu}"
  memory                   = "${var.container_memory}"

  lifecycle {
    ignore_changes = ["container_definitions"]
  }

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.container_cpu},
    "environment": [{
      "name": "APACHE_HTTP_PORT_NUMBER",
      "value": "${var.container_port}"
    },
    {
      "name": "SERVICE_LOOKUP_NAME",
      "value": "${module.service_label.id}"
      }],
    "portMappings": [
      {
        "containerPort": ${var.container_port}
      }
    ],
    "essential": true,
    "image": "${var.container_image}",
    "memory": ${var.container_memory},
    "memoryReservation": ${var.container_memoryreservation},
    "name": "${module.task_label.id}",
    "NetworkMode": "${var.network_mode}",
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "${aws_cloudwatch_log_group.main.name}",
            "awslogs-region": "${data.aws_region.default.name}",
            "awslogs-stream-prefix": "${data.aws_region.default.name}"
        }
    } 
  }
]
DEFINITION
}

data "aws_ecs_task_definition" "task" {
  task_definition = "${module.task_label.id}"
  depends_on      = ["aws_ecs_task_definition.task"]
}

module "tg_label" {
  source = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.1.3"

  namespace = "${var.namespace}"
  stage     = "${var.stage}"
  name      = "tg"
  tags      = "${var.tags}"
}

resource "aws_alb_target_group" "main" {
  name_prefix          = "${substr(module.tg_label.id, 0, 6)}"
  port                 = "${var.container_port}"
  protocol             = "${var.container_protocol}"
  vpc_id               = "${data.aws_vpc.default.id}"
  deregistration_delay = "${var.deregistration_delay}"
  target_type          = "instance"

  health_check {
    path                = "${var.health_check_path}"
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
    matcher             = "200-399"
  }

  tags = "${module.tg_label.tags}"

  lifecycle {
    create_before_destroy = "true"
  }
}

resource "aws_alb" "main" {
  name            = "${module.alb_label.id}"
  subnets         = ["${data.aws_subnet_ids.all.ids}"]
  security_groups = ["${aws_security_group.lb_sg.id}"]
  tags            = "${module.alb_label.tags}"
}

module "alb_label" {
  source = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.1.3"

  namespace = "${var.namespace}"
  stage     = "${var.stage}"
  name      = "alb"
  tags      = "${var.tags}"
}

# output "launch_specification" {
#   value = "${module.fleet.launch_specification}"
# }
output "user_data" {
  value = "${module.spot_launch_template.user_data}"
}

resource "aws_alb_listener" "front_end" {
  load_balancer_arn = "${aws_alb.main.id}"

  port     = "80"
  protocol = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.main.id}"
    type             = "forward"
  }
}

resource "aws_security_group" "lb_sg" {
  description = "controls access to the application ELB"

  vpc_id      = "${data.aws_vpc.default.id}"
  name_prefix = "${module.alb_label.id}"

  lifecycle {
    ignore_changes = ["ingress"]
  }

  tags = "${module.alb_label.tags}"
}

resource "aws_security_group_rule" "alb_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.lb_sg.id}"
}

resource "aws_security_group_rule" "alb_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.lb_sg.id}"
}

resource "aws_security_group_rule" "alb_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.lb_sg.id}"
}

resource "aws_security_group_rule" "allow_alb_in" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = "${aws_security_group.lb_sg.id}"
  security_group_id        = "${module.spot_launch_template.security_group_id}"
}

### Create the Task Role for the Container Task to run as.
resource "aws_iam_role" "task_role" {
  name = "${module.task_label.id}_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "execution_role_policy" {
  name = "${module.task_label.id}_role_policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "elasticloadbalancing:Describe*",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "ec2:Describe*",
        "ec2:AuthorizeSecurityGroupIngress",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
      ],
      "Resource": [
          "arn:aws:logs:*:*:*"
      ]
    }
  ]
}
EOF

  role = "${aws_iam_role.task_role.id}"
}

output "dns_address" {
  value = "${aws_alb.main.dns_name}"
}
