# run_sieves.tcl -- verify and time the six sieve variants.  Started by ../run_sieves.sh (cwd = package dir; BITARRAY_LIB and FRANK_PROCS come from the environment).
# Written by Claude (an AI model made by Anthropic) for Eric Taylor.
load [expr {[info exists ::env(BITARRAY_LIB)] ? $::env(BITARRAY_LIB) : [file join [pwd] libbitarray.so]}] Bitarray
source [expr {[info exists ::env(FRANK_PROCS)] ? $::env(FRANK_PROCS) : "sieve/frank_procs.tcl"}]
source sieve/variants.tcl
foreach need {run_sieve bits_to_primes} {
    if {![llength [info commands $need]]} {error "the sieve file does not define '$need' -- is it Frank van Bakel's Tcl sieve?"}
}

set known {11 5 100 25 1000 168 10000 1229 100000 9592 1000000 78498}
set variants {A run_sieve B run_sieve_B C run_sieve_C D run_sieve_D E run_sieve_E F run_sieve_F}
set names {A "A  Frank's sieve, unchanged" B "B  bit proc inlined, no extension"
           C "C  bitarray, lindex/lset" D "D  bitarray, fill step + next"
           E "E  bitarray 8-bit, lindex/lset" F "F  bitarray 8-bit, fill step + next"}
set ok 1

proc primes_of {v var} {
    upvar 1 $var p
    if {$v in {A B}} { return [bits_to_primes $p] }
    set w [expr {$v in {E F} ? 8 : 1}]
    if {[bitarray width $p] != $w} { error "variant $v result has width [bitarray width $p], expected $w" }
    if {![bitarray is $p]} { error "variant $v result is not a bitarray" }
    return [concat 2 [lmap i [lrange [lsearch -all $p 1] 1 end] {expr {2*$i+1}}]]
}

puts "tclsh:  [info nameofexecutable]   Tcl [info patchlevel]"
puts ""
puts "CORRECTNESS: number of primes found (expected count from the known table); all variants must also"
puts "             produce exactly the same list of primes as variant A"
puts [format "%9s %9s   %7s %7s %7s %7s %7s %7s   %s" limit expected A B C D E F "same list as A"]
foreach {limit expect} $known {
    set counts {}; set same {}; set lists {}
    foreach {v cmd} $variants {
        $cmd p $limit
        set l [primes_of $v p]
        lappend counts [llength $l]
        lappend lists $l
    }
    set sameAll 1
    foreach l $lists { if {$l ne [lindex $lists 0]} {set sameAll 0} }
    set countsOk 1
    foreach c $counts { if {$c != $expect} {set countsOk 0} }
    if {!$countsOk || !$sameAll} {set ok 0}
    puts [format "%9d %9d   %7d %7d %7d %7d %7d %7d   %s" $limit $expect {*}$counts [expr {$countsOk && $sameAll ? "yes" : "NO  <-- MISMATCH"}]]
}
puts ""

proc bench {cmd limit} {
    set best 1e99
    for {set r 0} {$r < 3} {incr r} {
        set t [lindex [timerate {$cmd p $limit} 1500] 0]
        if {$t < $best} {set best $t}
    }
    return $best
}
set limit 1000000
puts "TIMING: one full sieve pass at limit $limit, best of 3 (each timed for 1.5 s), microseconds"
puts [format "%-36s %14s %12s %10s" variant "us per pass" "passes/sec" "vs A"]
set base 0
foreach {v cmd} $variants {
    set t [bench $cmd $limit]
    if {$v eq "A"} {set base $t}
    puts [format "%-36s %14.1f %12.2f %9.1fx" [dict get $names $v] $t [expr {1e6/$t}] [expr {$base/$t}]]
}
puts ""
if {$ok} {
    puts "RESULT: PASS -- every variant found the right number of primes, and the same primes, at every limit"
    exit 0
} else {
    puts "RESULT: FAIL -- see the MISMATCH lines above"
    exit 1
}
