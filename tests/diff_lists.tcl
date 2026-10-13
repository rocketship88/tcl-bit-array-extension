# Differential: bitarray vs plain list of 0/1, same operations, compare results (value or error text).

proc norm {x} { return [join $x " "] }
proc try {script} { if {[catch {uplevel 1 $script} r]} {return [list ERR $r]} ; return [list OK $r] }
set fails 0
array set kept {}
proc tally {op obj} { global kept; if {![info exists kept($op)]} {set kept($op) {0 0}}; lset kept($op) [bitarray is $obj] [expr {[lindex $kept($op) [bitarray is $obj]]+1}] }
proc check {what l b} {
    global fails
    if {$l ne $b} { incr fails; if {$fails < 30} {puts "MISMATCH $what\n  list: $l\n  bita: $b"} }
}
expr {srand([lindex $argv 0])}
set N [lindex $argv 1]
set idxs {0 1 2 3 5 7 end end-1 end-2 end-5 -1 -3 100 end+1 end-100 1+1 2-1}
proc rbit {} { expr {int(rand()*2)} }
proc rlist {n} { set l {}; for {set i 0} {$i<$n} {incr i} {lappend l [rbit]}; return $l }
for {set it 0} {$it < $N} {incr it} {
    set n [expr {int(rand()*140)}]
    if {rand() < 0.2} {set n [lindex {0 1 63 64 65 127 128 129} [expr {int(rand()*8)}]]}
    set L [rlist $n]
    set B [bitarray newfrom $L]
    check "from str n=$n" $L [norm $B]
    check len [llength $L] [llength $B]
    for {set k 0} {$k < 12} {incr k} {
        set i [lindex $idxs [expr {int(rand()*[llength $idxs])}]]
        set j [lindex $idxs [expr {int(rand()*[llength $idxs])}]]
        set v [rbit]
        switch [expr {int(rand()*16)}] {
          0 { check "lindex $i" [try {lindex $L $i}] [try {lindex $B $i}] }
          1 { set rl [try {lset L $i $v}]; set rb [try {lset B $i $v}]
              check "lset $i $v n=$n" $rl $rb; check "after lset" $L [norm $B] }
          2 { tally lrange [lrange $B 0 end]; check "lrange $i $j" [try {lrange $L $i $j}] [try {norm [lrange $B $i $j]}] }
          3 { check lreverse [lreverse $L] [norm [lreverse $B]] }
          4 { set cnt [expr {int(rand()*4)}]; set ins [rlist $cnt]
              set rl [try {lreplace $L $i $j {*}$ins}]; set rb [try {lreplace $B $i $j {*}$ins}]
              check "lreplace $i $j $ins" $rl [list [lindex $rb 0] [norm [lindex $rb 1]]]
              if {[lindex $rl 0] eq "OK"} {tally lreplace [lindex $rb 1]; set L [lindex $rl 1]; set B [lindex $rb 1]} }
          5 { set cnt [expr {int(rand()*4)}]; set ins [rlist $cnt]
              set rl [try {linsert $L $i {*}$ins}]; set rb [try {linsert $B $i {*}$ins}]
              check "linsert $i $ins" $rl [list [lindex $rb 0] [norm [lindex $rb 1]]]
              if {[lindex $rl 0] eq "OK"} {tally linsert [lindex $rb 1]; set L [lindex $rl 1]; set B [lindex $rb 1]} }
          6 { set a 0; foreach x $L {incr a $x}; set c 0; foreach x $B {incr c $x}; check foreach $a $c
              if {![bitarray is $B]} {set B [bitarray newfrom $B]}; check count $a [bitarray count $B] }
          7 { check "in $v" [expr {$v in $L}] [expr {$v in $B}]; check "ni" [expr {$v ni $L}] [expr {$v ni $B}] }
          8 { check lsearch [lsearch $L $v] [lsearch $B $v] ; check "lsearch all" [lsearch -all $L $v] [lsearch -all $B $v] }
          9 { check lsort [lsort $L] [lsort $B] }
          10 { set C $B; set M $L; try {lset C 0 [expr {1-[lindex $C 0]}]} ; try {lset M 0 [expr {1-[lindex $M 0]}]}
               check "alias orig" $L [norm $B]; check "alias copy" $M [norm $C] }
          11 { set rl [try {lappend L $v}]; set rb [try {lappend B $v}]
               check lappend $rl [list [lindex $rb 0] [norm [lindex $rb 1]]] }
          12 { check "lindex nested" [try {lindex $L $i $j}] [try {lindex $B $i $j}] }
          13 { check "llength/concat" [llength [concat $L $L]] [llength [concat $B $B]]
               check "join" [join $L ,] [join $B ,]; check "lmap" [lmap x $L {expr {1-$x}}] [lmap x $B {expr {1-$x}}] }
          14 { if {![bitarray is $B]} {set B [bitarray newfrom $B]}
               check "next1" [expr {[lsearch $L 1]}] [bitarray next $B 0]
               set s [expr {int(rand()*($n+2))}]
               set ex -1; for {set q $s} {$q < [llength $L]} {incr q} { if {[lindex $L $q]==0} {set ex $q; break} }
               check "next0 $s" $ex [bitarray next $B $s 0] }
          15 { check "eq" [expr {$L eq [norm $B]}] 1; check "string len" [string length $L] [string length $B] }
        }
    }
}


