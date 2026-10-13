# Differential for growing, shrinking and inserting: bitarray vs plain list, arrays up to a few thousand elements
# (crosses the 4-word minimum capacity and several doublings).  Uses the globals argv (seed iterations) and fails.
expr {srand([lindex $argv 0])}
set N [lindex $argv 1]
proc rbits {n} { set l {}; for {set i 0} {$i < $n} {incr i} {lappend l [expr {int(rand()*2)}]}; return $l }
for {set it 0} {$it < $N} {incr it} {
    set start [lindex {0 1 63 64 65 255 256 257 300} [expr {int(rand()*9)}]]
    set L [rbits $start]
    set B [bitarray newfrom $L]
    for {set k 0} {$k < 40} {incr k} {
        set len [llength $L]
        set cnt [expr {int(rand()*(rand()<0.2 ? 200 : 8))}]
        set ins [rbits $cnt]
        set pos [expr {int(rand()*($len+1))}]
        switch [expr {int(rand()*7)}] {
          0 { lappend L {*}$ins; lappend B {*}$ins }
          1 { set L [linsert $L $pos {*}$ins]; set B [linsert $B $pos {*}$ins] }
          2 { set j [expr {min($len-1, $pos+int(rand()*100))}]
              set L [lreplace $L $pos $j]; set B [lreplace $B $pos $j] }
          3 { set j [expr {min($len-1, $pos+int(rand()*100))}]
              set L [lreplace $L $pos $j {*}$ins]; set B [lreplace $B $pos $j {*}$ins] }
          4 { set v [expr {int(rand()*2)}]; lset L [llength $L] $v; lset B [llength $B] $v }
          5 { set C $B; set M $L; lappend C {*}$ins; lappend M {*}$ins
              if {$L ne [join $B " "]} {incr fails; puts "GROW MISMATCH: appending to a copy changed the original"}
              if {$M ne [join $C " "]} {incr fails; puts "GROW MISMATCH: appending to a copy"} }
          6 { if {$len > 0} {
                  set i [expr {int(rand()*$len)}]; set v [expr {int(rand()*2)}]
                  lset L $i $v; lset B $i $v } }
        }
        if {$L ne [join $B " "]} {
            incr fails
            if {$fails < 10} {puts "GROW MISMATCH it=$it step=$k len(list)=[llength $L] len(bitarray)=[llength $B]"}
            break
        }
        if {![bitarray is $B]} {set B [bitarray newfrom $B]}
        set ones 0; foreach x $L {incr ones $x}
        if {[bitarray count $B] != $ones} {incr fails; puts "GROW MISMATCH count: [bitarray count $B] vs $ones"; break}
        set ex -1; set q [lsearch $L 0]
        if {[bitarray next $B 0 0] != $q} {incr fails; puts "GROW MISMATCH next0: [bitarray next $B 0 0] vs $q"; break}
    }
}
