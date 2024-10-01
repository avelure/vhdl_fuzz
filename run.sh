#!/bin/bash
docker build -t afl_ghdl ./

docker run \
	--mount type=bind,source="$(pwd)"/../afl_work,target=/work \
	-it afl_ghdl
