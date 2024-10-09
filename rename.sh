#!/bin/bash

rename_to_hash () {
	file=$1
	sum=`sha256sum "$file"`
	#remove the file name from sha256sum's output
	# this is using bash's pattern matching but can be swapped out
	sum="${sum%  $file}"
	mv "$file" "$sum"
}
export -f rename_to_hash

cd $1
echo "Hashing files"
find ./id* -maxdepth 1 -type f | parallel rename_to_hash
cd -