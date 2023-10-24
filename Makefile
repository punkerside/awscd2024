name       = container-demo
docker_uid = $(shell id -u)
docker_gid = $(shell id -g)
docker_who = $(shell whoami)

export AWS_DEFAULT_REGION=us-east-1
export DOCKER_BUILDKIT=0
export KUBECONFIG=/tmp/${name}

base:
	@docker build -t ${name}:base -f Dockerfile.base .
	@docker build -t ${name}:terraform --build-arg IMG=${name}:base -f Dockerfile.terraform .
	@docker build -t ${name}:packer --build-arg IMG=${name}:base -f Dockerfile.packer .

vpc:
	@echo "${docker_who}:x:${docker_uid}:${docker_gid}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/vpc:/app ${name}:terraform init
	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/vpc:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${name}:terraform apply -var="name=${name}" -auto-approve

build:
	@echo "${docker_who}:x:${docker_uid}:${docker_gid}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}:/app ${name}:packer init config.pkr.hcl
	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}:/app -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} ${name}:packer build -var 'name=${name}' config.pkr.hcl

jmeter:
	@echo "${docker_who}:x:${docker_uid}:${docker_gid}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/jmeter:/app ${name}:terraform init
	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/jmeter:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${name}:terraform apply -var="name=${name}" -auto-approve

ecs:
	@echo "${docker_who}:x:${docker_uid}:${docker_gid}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/ecs:/app ${name}:terraform init
	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/ecs:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${name}:terraform apply -var="name=${name}" -auto-approve

destroy:
	@echo "${docker_who}:x:${docker_uid}:${docker_gid}::/app:/sbin/nologin" > passwd
	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/passwd:/etc/passwd:ro -v ${PWD}/terraform/vpc:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${name}:terraform destroy -var="name=${name}" -auto-approve







# apply:
# 	@echo "${docker_who}:x:${docker_uid}:${docker_gid}::/app:/sbin/nologin" > terraform/passwd
# 	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/terraform/passwd:/etc/passwd:ro -v ${PWD}/terraform:/app ${name}:terraform init
# 	@docker run --rm -u ${docker_uid}:${docker_gid} -v ${PWD}/terraform/passwd:/etc/passwd:ro -v ${PWD}/terraform:/app -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} ${name}:terraform apply -var="name=${name}" -auto-approve

# cluster:
# 	@rm -rf ${KUBECONFIG}
# 	@aws eks update-kubeconfig --name ${name} --region ${AWS_DEFAULT_REGION}
# 	@kubectl patch deployment coredns -n kube-system --type json -p='[{"op": "remove", "path": "/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]'
# 	@kubectl rollout restart -n kube-system deployment coredns
# 	@kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# deploy:
# 	kubectl apply -f k8s/app.yaml
# 	kubectl apply -f k8s/ingress.yaml

