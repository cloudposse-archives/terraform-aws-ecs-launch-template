#!/bin/bash -xe
export PATH=/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:$PATH
yum -y update
yum -y install python27 python27-pip jq zip unzip perl-Switch perl-DateTime perl-Sys-Syslog perl-LWP-Protocol-https perl-Digest-SHA.x86_64
pip install awscli
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -c -r .region)
aws configure set default.region $REGION
curl https://aws-cloudwatch.s3.amazonaws.com/downloads/CloudWatchMonitoringScripts-1.2.2.zip -O
unzip CloudWatchMonitoringScripts-1.2.2.zip && rm -f CloudWatchMonitoringScripts-1.2.2.zip && cp -r aws-scripts-mon /opt/
echo "*/5 * * * * /opt/aws-scripts-mon/mon-put-instance-data.pl --mem-used-incl-cache-buff --mem-util --disk-space-util --disk-path=/ --from-cron" | crontab -
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config
cat <<EOF > /opt/awslogs.conf
[general]
state_file = /var/awslogs/state/agent-state
[/var/log/dmesg]
file = /var/log/dmesg
log_group_name = ${logsgroup}
log_stream_name = %ECS_CLUSTER/%CONTAINER_INSTANCE/var/log/dmesg
initial_position = start_of_file
[/var/log/messages]
file = /var/log/messages
log_group_name = ${logsgroup}
log_stream_name = %ECS_CLUSTER/%CONTAINER_INSTANCE/var/log/messages
datetime_format = %b %d %H:%M:%S
initial_position = start_of_file
[/var/log/docker]
file = /var/log/docker
log_group_name = ${logsgroup}
log_stream_name = %ECS_CLUSTER/%CONTAINER_INSTANCE/var/log/docker
datetime_format = %Y-%m-%dT%H:%M:%S.%f
initial_position = start_of_file
[/var/log/ecs/ecs-init.log]
file = /var/log/ecs/ecs-init.log*
log_group_name = ${logsgroup}
log_stream_name = %ECS_CLUSTER/%CONTAINER_INSTANCE/var/log/ecs/ecs-init.log
datetime_format = %Y-%m-%dT%H:%M:%SZ
initial_position = start_of_file
[/var/log/ecs/ecs-agent.log]
file = /var/log/ecs/ecs-agent.log*
log_group_name = ${logsgroup}
log_stream_name = %ECS_CLUSTER/%CONTAINER_INSTANCE/var/log/ecs/ecs-agent.log
datetime_format = %Y-%m-%dT%H:%M:%SZ
initial_position = start_of_file
[/var/log/ecs/audit.log]
file = /var/log/ecs/audit.log*
log_group_name = ${logsgroup}
log_stream_name = %ECS_CLUSTER/%CONTAINER_INSTANCE/var/log/ecs/audit.log
datetime_format = %Y-%m-%dT%H:%M:%SZ
initial_position = start_of_file
EOF
chmod 777 /opt/awslogs.conf
cat <<EOF > /etc/init/cloudwatch-logs-start.conf
description "Configure and start CloudWatch Logs agent on Amazon ECS container instance"
author "Amazon Web Services"
start on started ecs
script
exec 2>>/var/log/cloudwatch-logs-start.log
set -x
until curl -s http://localhost:51678/v1/metadata; do sleep 1; done
ECS_CLUSTER=\$(curl -s http://localhost:51678/v1/metadata | jq .Cluster | tr -d \")
CONTAINER_INSTANCE=\$(curl -s http://localhost:51678/v1/metadata | jq .ContainerInstanceArn | tr -d \" | awk -F'/' '{print \$2}')
REGION=\$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -c -r .region)
sed -i "s|%ECS_CLUSTER|\$ECS_CLUSTER|g" /opt/awslogs.conf
sed -i "s|%CONTAINER_INSTANCE|\$CONTAINER_INSTANCE|g" /opt/awslogs.conf
cd /tmp && curl -sO https://s3.amazonaws.com/aws-cloudwatch/downloads/latest/awslogs-agent-setup.py
python /tmp/awslogs-agent-setup.py -n -r \$REGION -c /opt/awslogs.conf
chkconfig awslogs on
service awslogs start
end script
EOF
cat <<EOF > /etc/init/spot-instance-termination-notice-handler.conf
description "Start spot instance termination handler monitoring script"
author "Amazon Web Services"
start on started ecs
script
echo \$\$ > /var/run/spot-instance-termination-notice-handler.pid
exec /usr/local/bin/spot-instance-termination-notice-handler.sh
end script
pre-start script
logger "[spot-instance-termination-notice-handler.sh]: spot instance termination notice handler started"
end script
EOF
cat <<EOF > /usr/local/bin/spot-instance-termination-notice-handler.sh
#!/bin/bash
while sleep 5; do
if [ -z \$(curl -Isf http://169.254.169.254/latest/meta-data/spot/termination-time)];
then
/bin/false
else
logger "[spot-instance-termination-notice-handler.sh]: spot instance termination notice detected"
STATUS=DRAINING
ECS_CLUSTER=\$(curl -s http://localhost:51678/v1/metadata | jq .Cluster | tr -d \")
CONTAINER_INSTANCE=\$(curl -s http://localhost:51678/v1/metadata | jq .ContainerInstanceArn | tr -d \")
logger "[spot-instance-termination-notice-handler.sh]: putting instance in state \$STATUS"
logger "[spot-instance-termination-notice-handler.sh]: running: /usr/local/bin/aws
ecs update-container-instances-state --cluster \$ECS_CLUSTER --container-instances \$CONTAINER_INSTANCE --status \$STATUS" --region ${region}
/usr/local/bin/aws ecs update-container-instances-state --cluster \$ECS_CLUSTER --container-instances \$CONTAINER_INSTANCE --status \$STATUS --region ${region}
logger "[spot-instance-termination-notice-handler.sh]: running: \"/usr/local/bin/aws sns publish --topic-arn ${snstopic} --message \"Spot instance termination notice detected. Details: cluster: \$ECS_CLUSTER, container_instance: \$CONTAINER_INSTANCE. Putting instance in state \$STATUS.\""
/usr/local/bin/aws sns publish --topic-arn ${snstopic} --message "Spot instance termination notice detected. Details: cluster: \$ECS_CLUSTER, container_instance: \$CONTAINER_INSTANCE. Putting instance in state \$STATUS." --region ${region}
logger "[spot-instance-termination-notice-handler.sh]: putting myself to sleep..."
sleep 120
fi
done
EOF
chmod +x /usr/local/bin/spot-instance-termination-notice-handler.sh
