NAME        = container-benchmark
DOCKER_UID  = $(shell id -u)
DOCKER_GID  = $(shell id -g)
DOCKER_USER = $(shell whoami)

export AWS_DEFAULT_REGION=us-east-1
export DOCKER_BUILDKIT=0
export KUBECONFIG=/tmp/${NAME}

remove:
# vpc
	@rm -rf terraform/vpc/.terraform/ && rm -rf terraform/vpc/.terraform.d/ && rm -rf terraform/vpc/.terraform.lock.hcl && rm -rf terraform/vpc/terraform.tfstate && rm -rf terraform/vpc/terraform.tfstate.backup
# ecs
	@rm -rf terraform/ecs/.terraform/ && rm -rf terraform/ecs/.terraform.d/ && rm -rf terraform/ecs/.terraform.lock.hcl && rm -rf terraform/ecs/terraform.tfstate && rm -rf terraform/ecs/terraform.tfstate.backup
# eks
	@rm -rf terraform/eks/.terraform/ && rm -rf terraform/eks/.terraform.d/ && rm -rf terraform/eks/.terraform.lock.hcl && rm -rf terraform/eks/terraform.tfstate && rm -rf terraform/eks/terraform.tfstate.backup
# psql
	@rm -rf terraform/psql/.terraform/ && rm -rf terraform/psql/.terraform.d/ && rm -rf terraform/psql/.terraform.lock.hcl && rm -rf terraform/psql/terraform.tfstate && rm -rf terraform/psql/terraform.tfstate.backup
# jmeter
	@rm -rf terraform/jmeter/.terraform/ && rm -rf terraform/jmeter/.terraform.d/ && rm -rf terraform/jmeter/.terraform.lock.hcl && rm -rf terraform/jmeter/terraform.tfstate && rm -rf terraform/jmeter/terraform.tfstate.backup

# creating base container images
base:
	@docker build -t ${NAME}:base -f docker/Dockerfile.base .
	@docker build -t ${NAME}:terraform --build-arg IMG=${NAME}:base -f docker/Dockerfile.terraform .
	@docker build -t ${NAME}:packer --build-arg IMG=${NAME}:base -f docker/Dockerfile.packer .
	@docker build -t ${NAME}:npm --build-arg IMG=${NAME}:base -f docker/Dockerfile.npm .
	@docker build -t $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:psql --build-arg IMG=${NAME}:base -f docker/Dockerfile.psql .

# creating vpc and container registry
vpc:
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/vpc:/app ${NAME}:terraform init
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/vpc:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform apply -var="name=${NAME}" -auto-approve

# creating rds 
rds:
	@aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
	@docker push $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:psql
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/psql:/app ${NAME}:terraform init
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/psql:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform apply -var="name=${NAME}" -auto-approve
	@make run-task

# provisioning database
run-task:
	aws ecs run-task  --cluster ${NAME}-psql --task-definition ${NAME}-psql:$(shell aws ecs describe-task-definition --task-definition ${NAME}-psql --region ${AWS_DEFAULT_REGION} | jq -r .taskDefinition.revision) --launch-type="FARGATE" --network-configuration '{ "awsvpcConfiguration": { "securityGroups": ["$(shell aws ec2 describe-security-groups --region ${AWS_DEFAULT_REGION} --filter Name=group-name,Values=${NAME}-psql | jq -r .SecurityGroups[0].GroupId)"], "subnets": ["$(shell aws ec2 describe-subnets --filters "Name=tag:Name,Values=${NAME}-private-${AWS_DEFAULT_REGION}c" --query "Subnets[*].SubnetId" --region ${AWS_DEFAULT_REGION} | jq -r .[0])"]}}' --region ${AWS_DEFAULT_REGION}

# releasing test application
release:
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/app:/app ${NAME}:npm
	@docker build -t $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:latest --build-arg IMG=${NAME}:base -f docker/Dockerfile.latest .
	@aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
	@docker push $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:latest

# creating ecs cluster
ecs:
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/ecs:/app ${NAME}:terraform init
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/ecs:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform apply -var="name=${NAME}" -auto-approve

# creating and provisioning eks cluster
eks:
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/eks:/app ${NAME}:terraform init
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/eks:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform apply -var="name=${NAME}" -auto-approve
	@rm -rf ${KUBECONFIG}
	@aws eks update-kubeconfig --name ${NAME} --region ${AWS_DEFAULT_REGION}
	@kubectl rollout restart -n kube-system deployment coredns
	@kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	@export NAME=${NAME} ACCOUNT_ID=$(shell aws sts get-caller-identity --query "Account" --output text) && envsubst < k8s/sa.yaml | kubectl apply -f -
	@helm repo add eks https://aws.github.io/eks-charts
	@helm repo update eks
	@helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=${NAME} --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller --set region=${AWS_DEFAULT_REGION} --set vpcId=$(shell aws ec2 describe-vpcs --filters Name=tag:Name,Values=${NAME} --region ${AWS_DEFAULT_REGION} | jq -r .Vpcs[0].VpcId)
	@export NAME=${NAME} AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} CERTIFICATE_ARN=$(shell aws acm list-certificates --query "CertificateSummaryList[?DomainName=='eks.punkerside.io'].CertificateArn" --output text --region ${AWS_DEFAULT_REGION}) DB_HOSTNAME=$(shell aws rds describe-db-instances --db-instance-identifier ${NAME} --region ${AWS_DEFAULT_REGION} | jq -r .DBInstances[0].Endpoint.Address) NAME=${NAME} ACCOUNT_ID=$(shell aws sts get-caller-identity --query "Account" --output text) && envsubst < k8s/app.yaml | kubectl apply -f -





# destroy infrastructure
destroy:
#	@export NAME=${NAME} AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} CERTIFICATE_ARN=${CERTIFICATE_ARN} DB_HOSTNAME=${DB_HOSTNAME} NAME=${NAME} ACCOUNT_ID=$(shell aws sts get-caller-identity --query "Account" --output text) && envsubst < k8s/app.yaml | kubectl delete -f -
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
#	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/jmeter:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve
#	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/ecs:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/eks:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve
#	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/psql:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve
#	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/vpc:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve





# # creando imagen de jmeter y aprovisionando servidor
# jmeter:
# 	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
# 	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}:/app ${NAME}:packer init config.pkr.hcl
# 	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}:/app -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} ${NAME}:packer build -var 'name=${NAME}' config.pkr.hcl
# 	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/jmeter:/app ${NAME}:terraform init
# 	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/jmeter:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform apply -var="name=${NAME}" -auto-approve

