#!/bin/bash
docker build \
	-t vhdl_fuzz .

docker run \
	--privileged \
	--mount type=bind,source="$(pwd)"/work,target=/work \
	--security-opt seccomp=unconfined \
	-it vhdl_fuzz
