data "aws_iam_policy_document" "ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com", "autoscaling.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "asg_role" {
  role       = "${aws_iam_role.ec2.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AutoScalingNotificationAccessRole"
}

resource "aws_iam_role" "ec2" {
  assume_role_policy = "${data.aws_iam_policy_document.ec2.json}"
  name_prefix        = "${module.label.id}-instance-role"
}

resource "aws_iam_role_policy_attachment" "instance_role" {
  role       = "${aws_iam_role.ec2.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role" "lambda" {
  assume_role_policy = "${data.aws_iam_policy_document.lambda.json}"
  name_prefix        = "${module.label.id}-lambda-role"
}

data "aws_iam_policy_document" "lambda" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "autoscaling.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_role" {
  role       = "${aws_iam_role.lambda.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AutoScalingNotificationAccessRole"
}

resource "aws_iam_role_policy" "lambda_policy" {
  name_prefix = "${module.label.id}-lambda-asg-policy"
  role        = "${aws_iam_role.lambda.name}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
            "autoscaling:CompleteLifecycleAction",
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "ec2:DescribeInstances",
            "ec2:DescribeInstanceAttribute",
            "ec2:DescribeInstanceStatus",
            "ec2:DescribeHosts",
            "ecs:ListClusters",
            "ecs:ListContainerInstances",
            "ecs:SubmitContainerStateChange",
            "ecs:SubmitTaskStateChange",
            "ecs:DescribeContainerInstances",
            "ecs:UpdateContainerInstancesState",
            "ecs:ListTasks",
            "ecs:DescribeTasks",
            "sns:Publish",
            "sns:ListSubscriptions"
        ],
    "Resource": ["*"]
  }]
}
EOF
}

resource "aws_iam_role_policy_attachment" "instance_role_logs" {
  role       = "${aws_iam_role.ec2.name}"
  policy_arn = "${aws_iam_policy.spot_fleet_logging_policy.arn}"
}

resource "aws_iam_instance_profile" "instance_profile" {
  role        = "${aws_iam_role.ec2.name}"
  name_prefix = "${module.label.id}-instance-profile"
}

# Allow Spot request to run and terminate EC2 instances
data "aws_iam_policy_document" "spotfleet" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["spotfleet.amazonaws.com", "ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "taggingrole" {
  assume_role_policy = "${data.aws_iam_policy_document.spotfleet.json}"
  name_prefix        = "${module.label.id}-tagging-role"
}

resource "aws_iam_role_policy_attachment" "spot_request_policy" {
  role       = "${aws_iam_role.taggingrole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = "${aws_iam_role.taggingrole.name}"
  policy_arn = "${aws_iam_policy.spot_fleet_policy.arn}"
}

resource "aws_iam_policy" "spot_fleet_policy" {
  name_prefix = "${module.label.id}-spot-fleet-policy"
  path        = "/"
  description = "Spot Fleet Request Account Policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
       "ec2:DescribeImages",
       "ec2:DescribeSubnets",
       "ec2:RequestSpotInstances",
       "ec2:TerminateInstances",
       "ec2:DescribeInstanceStatus",
       "iam:PassRole"
        ],
    "Resource": ["*"]
  }]
}
EOF
}

resource "aws_iam_role_policy" "asg_policy" {
  name_prefix = "${module.label.id}-asg-policy"
  role        = "${aws_iam_role.lambda.name}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
            "elasticloadbalancing:Describe*",
            "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
            "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
            "ec2:Describe*",
            "ec2:AuthorizeSecurityGroupIngress"
        ],
    "Resource": ["*"]
  }]
}
EOF
}

resource "aws_iam_policy" "spot_fleet_logging_policy" {
  name_prefix = "${module.label.id}-spot-fleet-logging-policy"
  path        = "/"
  description = "Spot Fleet Request Logging Policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
            "Sid": "EnableCreationAndManagementOfCloudwatchLogStreams",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams",
                "logs:GetLogEvents",
                "logs:DescribeLogGroups",
                "logs:CreateLogGroup"
            ],
            "Resource": [
                "arn:aws:logs:*:*:log-group:${aws_cloudwatch_log_group.default.name}*:log-stream:*",
                "arn:aws:logs:*:*:log-group:${aws_cloudwatch_log_group.default.name}:*"
            ]
        },
        {
      "Action": [
        "cloudwatch:PutMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "ec2:DescribeTags",
        "SNS:Publish"
      ],
      "Effect": "Allow",
      "Resource": [
        "*"
      ]
    }]
}
EOF
}
