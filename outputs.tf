# output "spot_request_state" {
#   value = "${aws_spot_fleet_request.default.spot_request_state}"
# }

# output "request_id" {
#   value = "${aws_spot_fleet_request.default.id}"
# }
output "security_group_id" {
  value = "${aws_security_group.default.id}"
}

output "cluster_name" {
  value = "${local.cluster_name}"
}

output "cluster_arn" {
  value = "${join("", aws_ecs_cluster.default.*.arn)}"
}

output "log_group" {
  value = "${aws_cloudwatch_log_group.default.name}"
}

output "user_data" {
  value = "${base64decode(data.template_cloudinit_config.config.rendered)}"
}

output "iam_instance_profile_arn" {
  value = "${local.iam_instance_profile_arn}"
}

output "launch_template_name" {
  value = "${aws_launch_template.default.name}"
}

output "launch_template_id" {
  value = "${aws_launch_template.default.id}"
}

output "launch_template_version" {
  value = "${aws_launch_template.default.latest_version}"
}
