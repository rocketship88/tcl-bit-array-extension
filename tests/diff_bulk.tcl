# Differential for bulk commands: fill (with step), count (with range), next, new, from, vs naive list code.

set fails 0
proc check {what a b} { global fails; if {$a ne $b} {incr fails; if {$fails<20} {puts "MISMATCH $what\n  ref:  $a\n  bita: $b"}} }
proc try {script} { if {[catch {uplevel 1 $script} r]} {return [list ERR $r]} ; return [list OK $r] }
expr {srand([lindex $argv 0])}
set N [lindex $argv 1]
set sizes {0 1 2 63 64 65 127 128 129 200 1000}
for {set it 0} {$it < $N} {incr it} {
    set n [lindex $sizes [expr {int(rand()*[llength $sizes])}]]
    if {rand()<0.5} {set n [expr {int(rand()*300)}]}
    set init [expr {int(rand()*2)}]
    set B [bitarray new $n $init]
    set L [lrepeat $n $init]
    check new $L [join $B " "]
    for {set k 0} {$k < 10} {incr k} {
        set f [expr {int(rand()*($n+3))-1}]; set l [expr {int(rand()*($n+3))-1}]
        set st [expr {1+int(rand()*(rand()<0.3 ? 140 : 5))}]
        set v [expr {int(rand()*2)}]
        switch [expr {int(rand()*4)}] {
          0 { # fill
              set rb [try {bitarray fill B $f $l $v $st}]
              if {$f > $l} { set rl [list OK {}] } elseif {$f<0 || $l>=$n} { set rl [list ERR "index \"[expr {$f<0?$f:$l}]\" out of range"] } else {
                  for {set i $f} {$i <= $l} {incr i $st} { lset L $i $v }; set rl [list OK {}] }
              check "fill $f $l $v $st n=$n" $rl $rb
              check "after fill" $L [join $B " "] }
          1 { # count whole and range
              set ref 0; foreach x $L {incr ref $x}
              check count $ref [bitarray count $B]
              set cf [expr {max(0,$f)}]; set cl [expr {min($n-1,$l)}]
              set ref 0; for {set i $cf} {$i <= $cl} {incr i} {incr ref [lindex $L $i]}
              check "count $f $l" $ref [bitarray count $B $f $l] }
          2 { # next
              set s [expr {int(rand()*($n+2))}]
              foreach val {0 1} {
                  set ref -1; for {set i $s} {$i < $n} {incr i} { if {[lindex $L $i]==$val} {set ref $i; break} }
                  check "next $s $val n=$n" $ref [bitarray next $B $s $val] } }
          3 { # alias safety: fill on a shared copy must not touch the original
              set C $B; set M $L
              bitarray fill C 0 end [expr {1-$v}] 1 
              if {$n>0} {set M [lrepeat $n [expr {1-$v}]]}
              check "alias orig" $L [join $B " "]; check "alias copy" $M [join $C " "] }
        }
    }
}

