# Sieve variants for comparison.  A = Frank van Bakel's run_sieve unchanged (from frank_procs.tcl).
# B = same algorithm and data structure (list of 32-bit words), `bit` proc inlined.
# C = same algorithm on a bitarray, lindex/lset per bit.
# D = bitarray plus bulk commands (fill with step, next).
# E = like C but one byte per flag (bitarray -width 8).
# F = like D but one byte per flag (bitarray -width 8).
proc run_sieve_B {primesName max} {
    upvar 1 $primesName primes
    set maxroot [expr {sqrt($max)}]
    set size [expr {$max/2}]
    if {$max % 2} { incr size }
    set nw [expr {($size+31)/32}]
    set primes [lrepeat $nw 0xFFFFFFFF]
    # mask out bits >= size (same as the original)
    for {set i $size} {$i < $nw*32} {incr i} {
        set e [expr {$i >> 5}]
        lset primes $e [expr {[lindex $primes $e] & ~(1 << ($i & 31))}]
    }
    set factor 1
    while {$factor < $maxroot} {
        set i [expr {$factor*3 + 1}]
        set step [expr {$factor*2 + 1}]
        while {$i < $size} {
            set e [expr {$i >> 5}]
            lset primes $e [expr {[lindex $primes $e] & ~(1 << ($i & 31))}]
            incr i $step
        }
        for {set i [expr {$factor+1}]} {$i < $size} {incr i} {
            if {[lindex $primes [expr {$i >> 5}]] & (1 << ($i & 31))} {
                set factor $i
                break
            }
        }
        if {$i >= $size} break
    }
}
proc run_sieve_C {primesName max} {
    upvar 1 $primesName primes
    set maxroot [expr {sqrt($max)}]
    set size [expr {$max/2}]
    if {$max % 2} { incr size }
    set primes [bitarray new $size 1]
    set factor 1
    while {$factor < $maxroot} {
        set i [expr {$factor*3 + 1}]
        set step [expr {$factor*2 + 1}]
        while {$i < $size} {
            lset primes $i 0
            incr i $step
        }
        for {set i [expr {$factor+1}]} {$i < $size} {incr i} {
            if {[lindex $primes $i]} {
                set factor $i
                break
            }
        }
        if {$i >= $size} break
    }
}
proc run_sieve_D {primesName max} {
    upvar 1 $primesName primes
    set maxroot [expr {sqrt($max)}]
    set size [expr {$max/2}]
    if {$max % 2} { incr size }
    set primes [bitarray new $size 1]
    set factor 1
    while {$factor < $maxroot} {
        set start [expr {$factor*3 + 1}]
        if {$start < $size} {
            bitarray fill primes $start end 0 [expr {$factor*2 + 1}]
        }
        set factor [bitarray next $primes [expr {$factor+1}]]
        if {$factor < 0} break
    }
}
proc run_sieve_E {primesName max} {
    upvar 1 $primesName primes
    set maxroot [expr {sqrt($max)}]
    set size [expr {$max/2}]
    if {$max % 2} { incr size }
    set primes [bitarray new $size 1 -width 8]
    set factor 1
    while {$factor < $maxroot} {
        set i [expr {$factor*3 + 1}]
        set step [expr {$factor*2 + 1}]
        while {$i < $size} {
            lset primes $i 0
            incr i $step
        }
        for {set i [expr {$factor+1}]} {$i < $size} {incr i} {
            if {[lindex $primes $i]} {
                set factor $i
                break
            }
        }
        if {$i >= $size} break
    }
}
proc run_sieve_F {primesName max} {
    upvar 1 $primesName primes
    set maxroot [expr {sqrt($max)}]
    set size [expr {$max/2}]
    if {$max % 2} { incr size }
    set primes [bitarray new $size 1 -width 8]
    set factor 1
    while {$factor < $maxroot} {
        set start [expr {$factor*3 + 1}]
        if {$start < $size} {
            bitarray fill primes $start end 0 [expr {$factor*2 + 1}]
        }
        set factor [bitarray next $primes [expr {$factor+1}]]
        if {$factor < 0} break
    }
}
# counts (not timed): number of primes <= max
proc count_A {primes} { llength [bits_to_primes $primes] }
proc count_B {primes} { count_A $primes }
proc count_C {primes} { bitarray count $primes }    ;# index 0 (the number 1) is set; the prime 2 is not stored: 1 + (count-1)
