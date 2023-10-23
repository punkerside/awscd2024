name       = container-demo
docker_uid = $(shell id -u)
docker_gid = $(shell id -g)
docker_who = $(shell whoami)

export AWS_DEFAULT_REGION=us-east-1
export DOCKER_BUILDKIT=0

base:
	docker build -t ${name}:base -f docker/Dockerfile.base .
	docker build -t ${name}:terraform --build-arg IMG=${name}:base -f docker/Dockerfile.terraform .

ecs:
	@echo "${docker_who}:x:${docker_uid}:${docker_gid}::/app:/sbin/nologin" > terraform/ecs/passwd
	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/terraform/ecs/passwd:/etc/passwd:ro -v ${PWD}/terraform/ecs:/app ${name}:terraform init
	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/terraform/ecs/passwd:/etc/passwd:ro -v ${PWD}/terraform/ecs:/app -v ${HOME}/.aws:/app/.aws -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} ${name}:terraform apply -var="name=${name}" -auto-approve

destroy:
	@echo "${docker_who}:x:${docker_uid}:${docker_gid}::/app:/sbin/nologin" > terraform/ecs/passwd
	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/terraform/ecs/passwd:/etc/passwd:ro -v ${PWD}/terraform/ecs:/app -v ${HOME}/.aws:/app/.aws -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} ${name}:terraform destroy -var="name=${name}" -auto-approve