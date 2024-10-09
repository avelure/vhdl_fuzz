#!/bin/bash

rename_to_hash () {
	file=$1
	sum=`sha256sum "$file"`
	#remove the file name from sha256sum's output
	# this is using bash's pattern matching but can be swapped out
	sum="${sum%  $file}"
	cp "$file" "/work/corpus/$sum"
}
export -f rename_to_hash

cd $1
find . -name *.vhd* -type f | parallel rename_to_hash
cd -