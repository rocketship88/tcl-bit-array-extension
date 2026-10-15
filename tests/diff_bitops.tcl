# Differential for the bitwise commands (0.6.0): and, or, xor, andnot, not, in all three forms (var array / var <- array /
# var <- array array), strict and -length zero, widths 1/8/16/32/64, vs naive element-by-element list code.
# usage: tclsh driver that loads the library, sets argv to "seed iterations", and sources this file.

set fails 0
proc check {what a b} { global fails; if {$a ne $b} {incr fails; if {$fails<20} {puts "MISMATCH $what\n  ref:  $a\n  bita: $b"}} }
proc try {script} { if {[catch {uplevel 1 $script} r]} {return [list ERR $r]} ; return [list OK $r] }
expr {srand([lindex $argv 0])}
set N [lindex $argv 1]
set sizes {0 1 2 7 8 9 63 64 65 127 128 129 200 1000}
proc rlen {} {
    global sizes
    if {rand() < 0.5} { return [expr {int(rand()*300)}] }
    return [lindex $sizes [expr {int(rand()*[llength $sizes])}]]
}
proc rval {w} {
    # a random value of width w; for 64 a signed value that uses the high bits too
    switch $w {
	1 { return [expr {int(rand()*2)}] }
	8 { return [expr {int(rand()*256)}] }
	16 { return [expr {int(rand()*65536)}] }
	32 { return [expr {int(rand()*4294967296)}] }
	64 {
	    set v [expr {(int(rand()*4294967296) << 32) | int(rand()*4294967296)}]
	    if {$v >= 9223372036854775808} { set v [expr {$v - 18446744073709551616}] }
	    return $v
	}
    }
}
proc rlist {n w} { set r {}; for {set i 0} {$i < $n} {incr i} { lappend r [rval $w] }; return $r }
proc model {op x y w} {
    # y shorter than x counts as 0; y longer is ignored
    set mask [expr {$w == 64 ? -1 : (1 << $w) - 1}]
    set ny [llength $y]; set r {}; set i 0
    foreach xv $x {
	set yv [expr {$i < $ny ? [lindex $y $i] : 0}]
	switch $op {
	    and    { lappend r [expr {$xv & $yv}] }
	    or     { lappend r [expr {$xv | $yv}] }
	    xor    { lappend r [expr {$xv ^ $yv}] }
	    andnot { lappend r [expr {$xv & ~$yv}] }
	    not    { lappend r [expr {~$xv & $mask}] }
	}
	incr i
    }
    return $r
}
for {set it 0} {$it < $N} {incr it} {
    set w [lindex {1 8 16 32 64} [expr {int(rand()*5)}]]
    set n1 [rlen]
    set n2 [expr {rand() < 0.4 ? $n1 : [rlen]}]
    set xl [rlist $n1 $w]; set yl [rlist $n2 $w]
    set X [bitarray newfrom $xl -width $w]
    set Y [bitarray newfrom $yl -width $w]
    set op [lindex {and or xor andnot not} [expr {int(rand()*5)}]]
    set zero [expr {rand() < 0.5}]
    set form [expr {int(rand()*3)}]    ;# 0: var array   1: var <- array   2: var <- array array
    set opts [expr {$zero ? "-length zero" : (rand() < 0.5 ? "-length strict" : "")}]
    set desc "$op $opts form=$form w=$w n1=$n1 n2=$n2"
    if {$op eq "not"} {
	set exp [model not $xl {} $w]
	switch $form {
	    0 { set V $X; set r [try {bitarray not V}] }
	    default { set r [try {bitarray not V <- $X}] }
	}
	check "$desc result" [list OK {}] $r
	check "$desc value" $exp [list {*}$V]
	check "$desc input unchanged" $xl [list {*}$X]
	continue
    }
    # the first input is X, the second Y; in form 2 the destination V is separate
    set bad [expr {!$zero && $n1 != $n2}]
    switch $form {
	0 { set V $X; set r [try {bitarray $op {*}[expr {$opts eq "" ? {} : $opts}] V $Y}] }
	1 { set V $X; set r [try {bitarray $op {*}[expr {$opts eq "" ? {} : $opts}] V <- $Y}] }
	2 { catch {unset V}; set r [try {bitarray $op {*}[expr {$opts eq "" ? {} : $opts}] V <- $X $Y}] }
    }
    if {$bad} {
	check "$desc error" ERR [lindex $r 0]
	check "$desc error leaves X" $xl [list {*}$X]
	if {$form == 2} { check "$desc no variable" 0 [info exists V] } else { check "$desc V unchanged" $xl [list {*}$V] }
	continue
    }
    set exp [model $op $xl $yl $w]
    check "$desc result" [list OK {}] $r
    check "$desc value" $exp [list {*}$V]
    check "$desc is bitarray" 1 [bitarray is $V]
    check "$desc width" $w [bitarray width $V]
    check "$desc length" $n1 [llength $V]
    check "$desc X (shared holder) unchanged" $xl [list {*}$X]
    check "$desc Y unchanged" $yl [list {*}$Y]
    # the result must still behave: grow it and compare with the list model
    set extra [rlist 70 $w]
    lappend V {*}$extra
    check "$desc after growth" [concat $exp $extra] [list {*}$V]
    set nz 0; foreach v [concat $exp $extra] { if {$v != 0} {incr nz} }
    check "$desc count" $nz [bitarray count $V]
}
puts "diff_bitops: seed [lindex $argv 0], $N iterations, $fails mismatches"
