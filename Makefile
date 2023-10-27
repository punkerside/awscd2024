NAME        = container-benchmark
DOCKER_UID  = $(shell id -u)
DOCKER_GID  = $(shell id -g)
DOCKER_USER = $(shell whoami)

export AWS_DEFAULT_REGION=us-east-1
export DOCKER_BUILDKIT=0
export KUBECONFIG=/tmp/${NAME}

# creando imagenes de contenedores base
base:
	@docker build -t ${NAME}:base -f docker/Dockerfile.base .
	@docker build -t ${NAME}:terraform --build-arg IMG=${NAME}:base -f docker/Dockerfile.terraform .
	@docker build -t ${NAME}:packer --build-arg IMG=${NAME}:base -f docker/Dockerfile.packer .
	@docker build -t ${NAME}:npm --build-arg IMG=${NAME}:base -f docker/Dockerfile.npm .

# creando vpc y registro de contenedores
vpc:
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/vpc:/app ${NAME}:terraform init
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/vpc:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform apply -var="name=${NAME}" -auto-approve

# liberando aplicacion de prueba
release:
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/app:/app ${NAME}:npm
	@docker build -t $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:latest --build-arg IMG=${NAME}:base -f docker/Dockerfile.latest .
	@aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
	@docker push $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:latest

# creando recursos de ecs
ecs:
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/ecs:/app ${NAME}:terraform init
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/ecs:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform apply -var="name=${NAME}" -auto-approve

# aprovisionando base de datos
psql:
	@docker build -t $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:psql --build-arg IMG=${NAME}:base -f docker/Dockerfile.psql .
	@aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
	@docker push $(shell aws sts get-caller-identity --query "Account" --output text).dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${NAME}:psql
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/psql:/app ${NAME}:terraform init
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/psql:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform apply -var="name=${NAME}" -auto-approve
	@aws ecs run-task  --cluster ${NAME} --task-definition ${NAME}-psql:$(shell aws ecs describe-task-definition --task-definition ${NAME}-psql --region ${AWS_DEFAULT_REGION} | jq -r .taskDefinition.revision) --launch-type="FARGATE" --network-configuration '{ "awsvpcConfiguration": { "securityGroups": ["$(shell aws ec2 describe-security-groups --region ${AWS_DEFAULT_REGION} --filter Name=group-name,Values=${NAME}-psql | jq -r .SecurityGroups[0].GroupId)"], "subnets": ["$(shell aws ec2 describe-subnets --filters "Name=tag:Name,Values=${NAME}-private-${AWS_DEFAULT_REGION}c" --query "Subnets[*].SubnetId" --region ${AWS_DEFAULT_REGION} | jq -r .[0])"]}}' --region ${AWS_DEFAULT_REGION}

# creando imagen de jmeter y aprovisionando servidor
jmeter:
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}:/app ${NAME}:packer init config.pkr.hcl
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}:/app -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} ${NAME}:packer build -var 'name=${NAME}' config.pkr.hcl
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/jmeter:/app ${NAME}:terraform init
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/jmeter:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform apply -var="name=${NAME}" -auto-approve

# eliminando infraestructura
destroy:
	@echo "${DOCKER_USER}:x:${DOCKER_UID}:${DOCKER_GID}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/psql:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/ecs:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/jmeter:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve
	@docker run --rm -u ${DOCKER_UID}:${DOCKER_GID} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/vpc:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${NAME}:terraform destroy -var="name=${NAME}" -auto-approve


























# cluster:
# 	@rm -rf ${KUBECONFIG}
# 	@aws eks update-kubeconfig --name ${NAME} --region ${AWS_DEFAULT_REGION}
# 	@kubectl patch deployment coredns -n kube-system --type json -p='[{"op": "remove", "path": "/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]'
# 	@kubectl rollout restart -n kube-system deployment coredns
# 	@kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# deploy:
# 	kubectl apply -f k8s/app.yaml
# 	kubectl apply -f k8s/ingress.yaml

