load ./libbitarray.so Bitarray
source sieve/frank_procs.tcl
source sieve/variants.tcl
set max [lindex $argv 0]
run_sieve primes $max;      set a [bits_to_primes $primes]
run_sieve_B primesB $max;   set b [bits_to_primes $primesB]
run_sieve_C primesC $max;   set c [concat 2 [lmap i [lrange [lsearch -all $primesC 1] 1 end] {expr {2*$i+1}}]]
run_sieve_D primesD $max;   set d [concat 2 [lmap i [lrange [lsearch -all $primesD 1] 1 end] {expr {2*$i+1}}]]
foreach v {E F} {
    run_sieve_$v primes$v $max
    set l$v [concat 2 [lmap i [lrange [lsearch -all [set primes$v] 1] 1 end] {expr {2*$i+1}}]]
}
puts "max=$max E=[llength $lE] F=[llength $lF] sameAE=[expr {$a eq $lE}] sameAF=[expr {$a eq $lF}] width E=[bitarray width $primesE] F=[bitarray width $primesF]"
puts "max=$max A=[llength $a] B=[llength $b] C=[llength $c] D=[llength $d] sameAB=[expr {$a eq $b}] sameAC=[expr {$a eq $c}] sameAD=[expr {$a eq $d}] bitarrayC=[bitarray is $primesC] D=[bitarray is $primesD]"
puts "count: [bitarray count $primesC] [bitarray count $primesD]"
