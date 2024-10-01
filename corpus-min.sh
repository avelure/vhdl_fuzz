#!/bin/bash

AFL_FAST_CAL=1 afl-fuzz -M ghdl -i /corpus -o /out -- ghdl -s --std=08 @@
 
