load ./libbitarray.so Bitarray
source sieve/frank_procs.tcl
source sieve/variants.tcl
set m [lindex $argv 0]
foreach v {A B C D E F} {
    set cmd [dict get {A {run_sieve p} B {run_sieve_B p} C {run_sieve_C p} D {run_sieve_D p} E {run_sieve_E p} F {run_sieve_F p}} $v]
    set best 1e99
    for {set r 0} {$r < 3} {incr r} {
        set t [lindex [timerate {{*}$cmd $m} 1500] 0]
        if {$t < $best} {set best $t}
    }
    puts [format "%s  %12.1f us/pass  (%.1f passes/sec)" $v $best [expr {1e6/$best}]]
}
