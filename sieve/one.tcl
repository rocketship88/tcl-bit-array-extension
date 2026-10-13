load ./libbitarray.so Bitarray
source sieve/frank_procs.tcl
source sieve/variants.tcl
set v [lindex $argv 0]; set m [lindex $argv 1]
switch $v { A {run_sieve p $m; puts "A [llength [bits_to_primes $p]]"} B {run_sieve_B p $m; puts "B [llength [bits_to_primes $p]]"} C {run_sieve_C p $m; puts "C [bitarray count $p]"} D {run_sieve_D p $m; puts "D [bitarray count $p]"} E {run_sieve_E p $m; puts "E [bitarray count $p]"} F {run_sieve_F p $m; puts "F [bitarray count $p]"} }
