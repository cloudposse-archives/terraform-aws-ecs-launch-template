# data "archive_file" "lambda_trigger_automation" {
#   type        = "zip"
#   source_file = "${path.module}/lambda/lambda-asg-drain.py"
#   output_path = "${path.module}/lambda/lambda-asg-drain.zip"
# }

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "${module.label.id}-AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda_trigger_asg_draining.function_name}"
  principal     = "sns.amazonaws.com"
  source_arn    = "${local.sns_topic_arn}"

  # qualifier      = "${aws_lambda_alias.test_alias.name}"
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = "${local.sns_topic_arn}"
  protocol  = "lambda"
  endpoint  = "${aws_lambda_function.lambda_trigger_asg_draining.arn}"
}

resource "aws_lambda_function" "lambda_trigger_asg_draining" {
  filename         = "${path.module}/lambda/lambda-asg-drain.zip"
  function_name    = "${module.label.id}-asg-ecs-draining"
  role             = "${aws_iam_role.lambda.arn}"
  handler          = "index.lambda_handler"
  description      = "Lambda code for the autoscaling hook triggers invoked when autoscaling events of launching and terminating instance occur"
  source_code_hash = "${base64sha256(file("${path.module}/lambda/lambda-asg-drain.zip"))}"
  runtime          = "python2.7"
  tags             = "${module.label.tags}"
  timeout          = "300"
}

resource "aws_autoscaling_lifecycle_hook" "default" {
  count                   = "${var.autoscaling_group_name != "" ? 1 : 0}"
  name                    = "autoscaling_group_terminate_ecs_drain"
  autoscaling_group_name  = "${var.autoscaling_group_name}"
  default_result          = "ABANDON"
  heartbeat_timeout       = 120
  lifecycle_transition    = "autoscaling:EC2_INSTANCE_TERMINATING"
  depends_on              = ["aws_iam_role_policy.asg_policy"]
  notification_target_arn = "${local.sns_topic_arn}"
  role_arn                = "${aws_iam_role.lambda.arn}"

  notification_metadata = <<EOF
{
  "clusterName": "${local.cluster_name}"
}
EOF
}
