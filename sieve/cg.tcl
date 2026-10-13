load ./libbitarray.so Bitarray
source sieve/frank_procs.tcl
source sieve/variants.tcl
set v $::env(V); set n $::env(N); set m $::env(M)
set cmd [dict get {A run_sieve B run_sieve_B C run_sieve_C D run_sieve_D E run_sieve_E F run_sieve_F} $v]
proc go {cmd n m} { for {set k 0} {$k < $n} {incr k} { $cmd p $m } }
go $cmd $n $m
