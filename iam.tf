data "aws_iam_policy_document" "node" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  assume_role_policy = "${data.aws_iam_policy_document.node.json}"
  name_prefix        = "${module.label.id}-instance-role"
}

resource "aws_iam_role_policy_attachment" "instance_role" {
  role       = "${aws_iam_role.ec2.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
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
        "ec2:DescribeTags"
      ],
      "Effect": "Allow",
      "Resource": [
        "*"
      ]
    }]
}
EOF
}
