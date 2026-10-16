# Differential for element widths 8, 16, 32 and 64 and the signed -8, -16, -32 and -64: bitarray vs a plain Tcl list under random operations.
# Uses the globals argv (seed iterations width) and fails (count of mismatches).
expr {srand([lindex $argv 0])}
set N [lindex $argv 1]
set W [lindex $argv 2]
set A [expr {abs($W)}]
if {$A == 64} { set lo -9223372036854775808; set hi 9223372036854775807 } elseif {$W < 0} { set lo [expr {-(1<<($A-1))}]; set hi [expr {(1<<($A-1))-1}] } else { set lo 0; set hi [expr {(1<<$W)-1}] }
proc rval {} {
    global lo hi W A
    switch [expr {int(rand()*8)}] {
        0 { return 0 }
        1 { return 1 }
        2 { return $hi }
        3 { return [expr {$hi - 1}] }
        4 { return $lo }
        5 { return [expr {$lo + 1}] }
        6 { return [expr {min($hi, int(rand()*100))}] }
        default {
            if {$A == 64} { return [expr {(int(rand()*4294967296) << 31 | int(rand()*2147483648)) * (rand()<0.5 ? 1 : -1)}] }
            return [expr {$lo + int(rand()*($hi-$lo+1))}]
        }
    }
}
proc rvals {n} { set l {}; for {set i 0} {$i < $n} {incr i} {lappend l [rval]}; return $l }
proc bad {what} { global fails it k; incr fails; if {$fails < 10} {puts "WIDTH MISMATCH w=$::W it=$it step=$k: $what"} }
proc naive_fill {Lname first last v step} {
    upvar 1 $Lname L
    for {set i $first} {$i <= $last} {incr i $step} { lset L $i $v }
}
for {set it 0} {$it < $N} {incr it} {
    set start [lindex {0 1 7 8 9 31 32 33 63 64 65 255 256 300} [expr {int(rand()*14)}]]
    set L [rvals $start]
    set B [bitarray newfrom $L -width $W]
    set k 0
    if {[bitarray width $B] != $W} { bad "width query" }
    for {set k 1} {$k <= 40} {incr k} {
        set len [llength $L]
        set cnt [expr {int(rand()*(rand()<0.2 ? 200 : 8))}]
        set ins [rvals $cnt]
        set pos [expr {int(rand()*($len+1))}]
        set op [expr {int(rand()*12)}]; set lossOk 0
        if {$op == 1 && $cnt == 1 && $pos >= $len} { set lossOk 1 }   ;# core returns an ordinary list here
        switch $op {
          0 { lappend L {*}$ins; lappend B {*}$ins }
          1 { set L [linsert $L $pos {*}$ins]; set B [linsert $B $pos {*}$ins] }
          2 { set j [expr {min($len-1, $pos+int(rand()*100))}]
              set L [lreplace $L $pos $j]; set B [lreplace $B $pos $j] }
          3 { set j [expr {min($len-1, $pos+int(rand()*100))}]
              set L [lreplace $L $pos $j {*}$ins]; set B [lreplace $B $pos $j {*}$ins] }
          4 { set v [rval]; lset L [llength $L] $v; lset B [llength $B] $v }
          5 { if {$len > 0} { set i [expr {int(rand()*$len)}]; set v [rval]; lset L $i $v; lset B $i $v } }
          6 { if {$len > 0} {
                  set a [expr {int(rand()*$len)}]; set b2 [expr {int(rand()*$len)}]
                  if {[lrange $L $a $b2] ne [join [lrange $B $a $b2] " "]} { bad "lrange $a $b2" }
                  if {[lreverse $L] ne [join [lreverse $B] " "]} { bad lreverse }
                  set R [lrange $B $a $b2]
                  if {$R ne "" && [bitarray width $R] != $W} { bad "slice lost its width" }
              } }
          7 { if {$len > 0} {
                  set a [expr {int(rand()*$len)}]; set b2 [expr {min($len-1, $a+int(rand()*70))}]
                  set st [expr {1+int(rand()*(rand()<0.3 ? 40 : 5))}]; set v [rval]
                  naive_fill L $a $b2 $v $st
                  bitarray fill B $a $b2 $v $st
              } }
          8 { set C $B; set M $L; lappend C {*}$ins; lappend M {*}$ins
              if {$L ne [join $B " "]} { bad "appending to a copy changed the original" }
              if {$M ne [join $C " "]} { bad "append to a copy" } }
          9 { set v [expr {$len && rand()<0.7 ? [lindex $L [expr {int(rand()*$len)}]] : [rval]}]
              if {($v in $B) != ($v in $L)} { bad "in $v" }
              foreach odd [list "0x[format %x [expr {abs($v) % 4096}]]" " $v" "+$v" "00$v"] {
                  if {($odd in $B) != ($odd in $L)} { bad "in '$odd'" }
              } }
          10 { if {[lsort -integer $L] ne [join [lsort -integer $B] " "]} { bad lsort }
               set s 0; foreach x $B { incr s [expr {$x % 7}] }
               set s2 0; foreach x $L { incr s2 [expr {$x % 7}] }
               if {$s != $s2} { bad foreach }
               if {$len && [lindex $B end] != [lindex $L end]} { bad "lindex end" } }
          11 { if {$len > 0} {
                  set v [expr {rand()<0.5 ? [lindex $L [expr {int(rand()*$len)}]] : 0}]
                  set a [expr {int(rand()*$len)}]; set b2 [expr {$a+int(rand()*($len-$a))}]
                  set nz 0; set eq 0
                  for {set i $a} {$i <= $b2} {incr i} { set e [lindex $L $i]; if {$e != 0} {incr nz}; if {$e == $v} {incr eq} }
                  if {[bitarray count $B $a $b2] != $nz} { bad "count nonzero $a $b2" }
                  if {[bitarray count $B $a $b2 $v] != $eq} { bad "count =$v $a $b2" }
                  set nzAll 0; foreach e $L { if {$e != 0} {incr nzAll} }
                  if {[bitarray count $B] != $nzAll} { bad "count all" }
                  set s [expr {int(rand()*$len)}]
                  set qn -1; set qe -1
                  for {set i $s} {$i < $len} {incr i} {
                      set e [lindex $L $i]
                      if {$qn < 0 && $e != 0} {set qn $i}
                      if {$qe < 0 && $e == $v} {set qe $i}
                  }
                  if {[bitarray next $B $s] != $qn} { bad "next nonzero $s" }
                  if {[bitarray next $B $s $v] != $qe} { bad "next =$v $s" }
              } }
        }
        if {$L ne [join $B " "]} { bad "contents: len(list)=[llength $L] len(bitarray)=[llength $B]"; break }
        if {![bitarray is $B]} {
            if {!$lossOk} { bad "lost the bitarray type (op $op)" }
            set B [bitarray newfrom $B -width $W]
        }
        if {[bitarray width $B] != $W} { bad "width changed to [bitarray width $B]"; break }
    }
}
