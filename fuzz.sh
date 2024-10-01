#!/bin/bash

readonly CMD_UNDER_TEST="/usr/local/bin/ghdl -s --std=08 @@"

fuzz() {
	echo "Don't forget to update the corpus with the data from /wor/corpus_new!"
	echo "Running fuzzer, you can start multiple containers for multithreading"
	afl-fuzz -M ghdl -i /work/corpus -o /work/afl -- $CMD_UNDER_TEST
	chmod -R 777 /work
}

# Rename file in current directory to its hash, performs deduplication based on content
rename_to_hash () {
	file=$1
	sum=`sha256sum "$file"`
	#remove the file name from sha256sum's output
	# this is using bash's pattern matching but can be swapped out
	sum="${sum%  $file}"
	mv "$file" "$sum"
}
export -f rename_to_hash

# Execute rename in parallel
parallel_rename_to_hash () {
	echo "Hashing files"
	find ./ -maxdepth 1 -type f | parallel rename_to_hash
}

count_files () {
	file_cnt=`ls -1 | wc -l`
	echo "There are $file_cnt files"
}

corpus_collect () {
	echo "Collecting corpus..."
	rm -R /work/cur_corpus
	mkdir /work/cur_corpus

	# Get files from AFL queue, no name clashes since AFL has a different naming scheme
	cp /work/afl/ghdl/queue/* /work/cur_corpus

	cd /work/cur_corpus
	parallel_rename_to_hash
	count_files
	cd /
	echo "Done"
}

corpus_cmin () {
	echo "Performing corpus minimization..."
	rm -R /work/corpus_cmin
	mkdir /work/corpus_cmin
	afl-cmin -i /work/cur_corpus -o /work/corpus_cmin -- $CMD_UNDER_TEST
	cd /work/corpus_cmin
	count_files
	cd /
	echo "Done"
}

corpus_tmin () {
	echo "Minimizing test cases..."
	mkdir -p /work/corpus_new
	# Don't delete stuff at the tmin step since it may take ages

	# find all input files, pipe to next command, {\} strips path
	find /work/corpus_cmin -maxdepth 1 -type f |
	parallel afl-tmin -i {} -o /work/corpus_new/{/} -- $CMD_UNDER_TEST

	cd /work/corpus_new
	parallel_rename_to_hash
	count_files
	cd /
	echo "Done"
}

corpus_prune() {
	corpus_collect
	corpus_cmin
	corpus_tmin
	chmod -R 777 /work
}

crashes_collect () {
	mkdir /work/cur_crashes
	# Get crashes from AFL
	cp /work/afl/ghdl/crashes/* /work/cur_crashes

	cd /work/cur_crashes
	rename_to_hash 
	cd /
	
	echo "Collecting crashes"
	mkdir /work/cur_crashes
	# Get files from AFL queue, no name clashes since AFL has a different naming scheme
	cp /work/afl/ghdl/crashes /work/cur_crashes

	cd /work/cur_crashes
	parallel_rename_to_hash
	count_files
	cd /
	echo "Done"
}

crashes_cmin () {
	echo "Deduplicating crashes..."
	afl-cmin -C -i /work/cur_crashes -o /work/crashes_cmin -- $CMD_UNDER_TEST
	cd /work/crashes_cmin
	count_files
	cd /
}

crashes_tmin () {
	echo "Minimizing crashes..."
	mkdir -p /work/crashes_new
	
	# find all input files, pipe to next command, {\} strips path
	find /work/crashes_cmin -maxdepth 1 -type f |
	parallel afl-tmin -i {} -o /work/crashes_new/{/} -- $CMD_UNDER_TEST

	cd /work/crashes_new
	parallel_rename_to_hash
	count_files
	cd /
	echo "Done"
}

crash_prune () {
	crashes_collect
	crashes_cmin
	crashes_tmin
	chmod -R 777 /work
}

helptext () {
	echo "Supported commands are:"
	echo "  fuzz         Run the fuzzing process"
	echo "  corpus_prune Minimize and deduplicate the corpus for better efficiency"
	echo "  crash_prune  Minimize and deduplicate all crashes for better debugging"
}

case $1 in
	fuzz)
		fuzz
		;;
	corpus_prune)
		corpus_prune
		;;
	crash_prune)
		crash_prune
		;;
	*)
		helptext
		;;
esac


