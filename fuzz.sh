#!/bin/bash
readonly CMD_GHDL="/usr/local/bin/ghdl -s --std=08 -fsynopsys -frelaxed -fno-diagnostics-show-option -fno-caret-diagnostics -fpsl --mb-comments -fmax-errors=1 -Wno-library -Wno-port -Wno-pragma -Wno-specs -Wno-runtime-error -Wno-missing-wait -Wno-shared -Wno-hide -Wno-pure -Wno-analyze-assert -Wno-attribute -Wno-useless -Wno-conformance -Wno-elaboration"
readonly CMD_NVC="/usr/local/bin/nvc --std=08 --messages=compact --ignore-time -a --relaxed --error-limit=1 --psl"
# For targets that read from a file, AFL will replace "@@" in the string with the file
CMD_UNDER_TEST_INPUT_GHDL="@@"
# NVC supports reading from stdin with '-'
CMD_UNDER_TEST_INPUT_NVC="-"

CMD_UNDER_TEST=$CMD_NVC
CMD_UNDER_TEST_INPUT=$CMD_UNDER_TEST_INPUT_NVC
CMD_UNDER_TEST_AFL="$CMD_UNDER_TEST $CMD_UNDER_TEST_INPUT"
TARGET="nvc"

fuzz() {
    afl-system-config
	echo "Don't forget to update the corpus with the data from /wor/corpus_new!"
	echo "Running fuzzer, you can start multiple containers for multithreading"
	afl-fuzz -a text -e vhd -x /vhdl_dict.txt -M $TARGET -i /work/corpus -o /work/afl -- $CMD_UNDER_TEST_AFL
	chmod -R 777 /work/afl
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
	mkdir -p /work/$TARGET/cur_corpus

	# Get files from AFL queue, no name clashes since AFL has a different naming scheme
	cp /work/afl/$TARGET/queue/id* /work/$TARGET/cur_corpus
	cp /work/afl/$TARGET/crashes/id* /work/$TARGET/cur_corpus
	cp /work/afl/$TARGET/hangs/id* /work/$TARGET/cur_corpus

	cd /work/$TARGET/cur_corpus
	parallel_rename_to_hash
	count_files
	cd /
	echo "Done"
}

corpus_cmin () {
	echo "Performing corpus minimization..."
	rm -R /work/$TARGET/corpus_cmin
	mkdir -p /work/$TARGET/corpus_cmin
	afl-cmin -A -T all -i /work/$TARGET/cur_corpus -o /work/$TARGET/corpus_cmin -- $CMD_UNDER_TEST_AFL
	cd /work/$TARGET/corpus_cmin
	count_files
	cd /
	echo "Done"
}

corpus_tmin () {
	echo "Minimizing test cases..."
	mkdir -p /work/$TARGET/corpus_new
	# Don't delete stuff at the tmin step since it may take ages

	# find all input files, pipe to next command, {/} strips path
	find /work/$TARGET/corpus_cmin -maxdepth 1 -type f |
	parallel afl-tmin -i {} -o /work/$TARGET/corpus_new/{/} -- $CMD_UNDER_TEST_AFL

	cd /work/$TARGET/corpus_new
	parallel_rename_to_hash
	count_files
	cd /
	echo "Done"
}

corpus_prune() {
	corpus_collect
	corpus_cmin
	corpus_tmin
	chmod -R 777 /work/$TARGET/cur_corpus
	chmod -R 777 /work/$TARGET/corpus_cmin
	chmod -R 777 /work/$TARGET/corpus_new
}

crashes_collect () {
	echo "Collecting crashes"
	mkdir -p /work/$TARGET/cur_crashes
	# Get files from AFL queue, no name clashes since AFL has a different naming scheme
	cp /work/afl/$TARGET/crashes/id* /work/cur_crashes

	cd /work/$TARGET/cur_crashes
	parallel_rename_to_hash
	count_files
	cd /
	echo "Done"
}

crashes_cmin () {
	echo "Deduplicating crashes..."
	afl-cmin -C -T all -i /work/$TARGET/cur_crashes -o /work/$TARGET/crashes_cmin -- $CMD_UNDER_TEST_AFL
	cd /work/$TARGET/crashes_cmin
	count_files
	cd /
}

crashes_tmin () {
	echo "Minimizing crashes..."
	mkdir -p /work/$TARGET/crashes_new
	
	# find all input files, pipe to next command, {/} strips path
	find /work/$TARGET/crashes_cmin -maxdepth 1 -type f |
	parallel afl-tmin -i {} -o /work/$TARGET/crashes_new/{/} -- $CMD_UNDER_TEST_AFL

	cd /work/$TARGET/crashes_new
	parallel_rename_to_hash
	count_files
	cd /
	echo "Done"
}

crashes_report () {
	echo "Reporting crashes..."
	cd /work/$TARGET/crashes_new
	
	mkdir -p /work/$TARGET/crashes_new
	
	# find all input files, pipe to next command
	find /work/$TARGET/crashes_new -maxdepth 1 -type f -exec $CMD_UNDER_TEST {} \; >> /work/$TARGET/crashes_report.txt

	cd /
	echo "Done"
}

crash_prune () {
	crashes_collect
	crashes_cmin
	crashes_tmin
	crashes_report
	chmod -R 777 /work/$TARGET/cur_crashes
	chmod -R 777 /work/$TARGET/crashes_cmin
	chmod -R 777 /work/$TARGET/crashes_new
}

hangs_collect () {
	echo "Collecting hangs"
	mkdir -p /work/$TARGET/cur_hangs
	# Get files from AFL queue, no name clashes since AFL has a different naming scheme
	cp /work/afl/$TARGET/hangs/id* /work/$TARGET/cur_hangs

	cd /work/$TARGET/cur_hangs
	parallel_rename_to_hash
	count_files
	cd /
	echo "Done"
}

hangs_cmin () {
	echo "Deduplicating hangs..."
	afl-cmin -C -T all -i /work/$TARGET/cur_hangs -o /work/$TARGET/hangs_cmin -- $CMD_UNDER_TEST_AFL
	cd /work/$TARGET/hangs_cmin
	count_files
	cd /
}

hangs_tmin () {
	echo "Minimizing hangs..."
	mkdir -p /work/$TARGET/hangs_new
	
	# find all input files, pipe to next command, {\} strips path
	find /work/$TARGET/hangs_cmin -maxdepth 1 -type f |
	parallel afl-tmin -H -i {} -o /work/$TARGET/hangs_new/{/} -- $CMD_UNDER_TEST_AFL

	cd /work/$TARGET/hangs_new
	parallel_rename_to_hash
	count_files
	cd /
	echo "Done"
}

hangs_prune () {
	hangs_collect
	hangs_cmin
	hangs_tmin
	chmod -R 777 /work/$TARGET/cur_hangs
	chmod -R 777 /work/$TARGET/hangs_cmin
	chmod -R 777 /work/$TARGET/hangs_new
}

helptext () {
	echo "Supported commands are:"
	echo "  fuzz         Run the fuzzing process"
	echo "  corpus_prune Minimize and deduplicate the corpus for better efficiency"
	echo "  crash_prune  Minimize and deduplicate all crashes for better debugging"
	echo "  hangs_prune  Minimize and deduplicate all hangs for better debugging"
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
	hangs_prune)
		hangs_prune
		;;		
	*)
		helptext
		;;
esac


