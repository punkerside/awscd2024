name       = container-demo
docker_uid = $(shell id -u)
docker_gid = $(shell id -g)
docker_who = $(shell whoami)

export DOCKER_BUILDKIT=0

base:
	docker build -t ${name}:base -f docker/Dockerfile.base .
	docker build -t ${name}:terraform --build-arg IMG=${name}:base -f docker/Dockerfile.terraform .