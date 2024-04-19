NAME        = container-benchmark
DOCKER_UID  = $(shell id -u)
DOCKER_GID  = $(shell id -g)
DOCKER_USER = $(shell whoami)

AWS_DOMAIN  = punkerside.io
KUBECONFIG  = /tmp/${NAME}

export AWS_DEFAULT_REGION=us-east-1
export DOCKER_BUILDKIT=0

# creating base container images
base:
	@docker build -t ${NAME}:base -f docker/Dockerfile.base .
	@docker build -t ${NAME}:npm --build-arg IMG=${NAME}:base -f docker/Dockerfile.npm .
	@docker build -t $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:psql --build-arg IMG=${NAME}:base -f docker/Dockerfile.psql .

# creating vpc and container registry
vpc:
	@cd terraform/vpc/ && terraform init
	@cd terraform/vpc/ && terraform apply -var="name=${NAME}" -auto-approve

# provisioning ami for jmeter
ami:
	@packer init config.pkr.hcl
	@packer build -var "name=${NAME}" config.pkr.hcl

# provisioning server for jmeter
jmeter:
	@cd terraform/jmeter/ && terraform init
	@cd terraform/jmeter/ && terraform apply -var="name=${NAME}" -auto-approve

# deploying dependencies
dependencies:
# deploying demo application
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/app:/app ${NAME}:npm
	@docker build -t $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:latest --build-arg IMG=${NAME}:base -f docker/Dockerfile.latest .
	@aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
	@docker push $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:latest
# creating psql server in rds
	@docker push $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:psql
	@cd terraform/psql/ && terraform init
	@cd terraform/psql/ && terraform apply -var="name=${NAME}" -auto-approve
	@make run-task

# provisioning database
run-task:
	@aws ecs run-task --cluster ${NAME}-psql --task-definition ${NAME}-psql:$(shell aws ecs describe-task-definition --task-definition ${NAME}-psql --region ${AWS_DEFAULT_REGION} | jq -r .taskDefinition.revision) --launch-type="FARGATE" --network-configuration '{ "awsvpcConfiguration": { "securityGroups": ["$(shell aws ec2 describe-security-groups --region ${AWS_DEFAULT_REGION} --filter Name=group-name,Values=${NAME}-psql | jq -r .SecurityGroups[0].GroupId)"], "subnets": ["$(shell aws ec2 describe-subnets --filters "Name=tag:Name,Values=${NAME}-private-${AWS_DEFAULT_REGION}c" --query "Subnets[*].SubnetId" --region ${AWS_DEFAULT_REGION} | jq -r .[0])"]}}' --region ${AWS_DEFAULT_REGION}

# creating ecs cluster
ecs:
	@cd terraform/ecs/ && terraform init
	@cd terraform/ecs/ && terraform apply -var="name=${NAME}" -var="domain=${AWS_DOMAIN}" -auto-approve

# creating and provisioning eks cluster
eks:
	@cd terraform/eks/ && terraform init
	@cd terraform/eks/ && terraform apply -var="name=${NAME}" -auto-approve
	@rm -rf ${KUBECONFIG}
	@aws eks update-kubeconfig --name ${NAME} --region ${AWS_DEFAULT_REGION}
	@kubectl rollout restart -n kube-system deployment coredns
	@kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	@export NAME=${NAME} ACCOUNT_ID=$(shell aws sts get-caller-identity --query "Account" --output text) && envsubst < k8s/sa.yaml | kubectl apply -f -
	@helm repo add eks https://aws.github.io/eks-charts
	@helm repo update eks
	@helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=${NAME} --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller --set region=${AWS_DEFAULT_REGION} --set vpcId=$(shell aws ec2 describe-vpcs --filters Name=tag:Name,Values=${NAME} --region ${AWS_DEFAULT_REGION} | jq -r .Vpcs[0].VpcId)
	@export NAME=${NAME} AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} CERTIFICATE_ARN=$(shell aws acm list-certificates --query "CertificateSummaryList[?DomainName=='eks.punkerside.io'].CertificateArn" --output text --region ${AWS_DEFAULT_REGION}) DB_HOSTNAME=$(shell aws rds describe-db-instances --db-instance-identifier ${NAME} --region ${AWS_DEFAULT_REGION} | jq -r .DBInstances[0].Endpoint.Address) ACCOUNT_ID=$(shell aws sts get-caller-identity --query "Account" --output text) && envsubst < k8s/app.yaml | kubectl apply -f -

# config eks cluster
eks-config:
	@rm -rf /tmp/sample.json && cp terraform/eks/sample.json /tmp/sample.json
	@sed -i 's|varHostedZoneId|'$(shell aws elbv2 describe-load-balancers --names ${NAME}-eks --region ${AWS_DEFAULT_REGION} | jq -r .LoadBalancers[0].CanonicalHostedZoneId)'|g' /tmp/sample.json
	@sed -i 's|varDNSName|'$(shell aws elbv2 describe-load-balancers --names container-benchmark-eks --region us-east-1 | jq -r .LoadBalancers[0].DNSName)'|g' /tmp/sample.json
	@aws route53 change-resource-record-sets --hosted-zone-id $(shell aws route53 list-hosted-zones --query "HostedZones[?Name=='${AWS_DOMAIN}.'].Id" --output text | cut -d "/" -f3) --change-batch file:///tmp/sample.json

# destroy all infrastructure
destroy:
#	@kubectl delete ingress container-benchmark
	@cd terraform/jmeter/ && terraform destroy -var="name=${NAME}" -auto-approve
	@cd terraform/ecs/ && terraform destroy -var="name=${NAME}" -var="domain=${AWS_DOMAIN}" -auto-approve
	@cd terraform/eks/ && terraform destroy -var="name=${NAME}" -auto-approve
	@cd terraform/psql/ && terraform destroy -var="name=${NAME}" -auto-approve
	@cd terraform/vpc/ && terraform destroy -var="name=${NAME}" -auto-approve
	@rm -rf /tmp/sample.json && cp terraform/eks/sample.json /tmp/sample.json
	@sed -i 's|varHostedZoneId|'$(shell aws elbv2 describe-load-balancers --names ${NAME}-eks --region ${AWS_DEFAULT_REGION} | jq -r .LoadBalancers[0].CanonicalHostedZoneId)'|g' /tmp/sample.json
	@sed -i 's|varDNSName|'$(shell aws elbv2 describe-load-balancers --names container-benchmark-eks --region us-east-1 | jq -r .LoadBalancers[0].DNSName)'|g' /tmp/sample.json
	@sed -i 's|CREATE|DELETE|g' /tmp/sample.json
	@aws route53 change-resource-record-sets --hosted-zone-id $(shell aws route53 list-hosted-zones --query "HostedZones[?Name=='${AWS_DOMAIN}.'].Id" --output text | cut -d "/" -f3) --change-batch file:///tmp/sample.json
