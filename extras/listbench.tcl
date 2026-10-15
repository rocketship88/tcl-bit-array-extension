# listbench.tcl -- time the Tcl list commands on a plain list and on a bitarray, at three sizes.
# Written by Claude (an AI model made by Anthropic) for Eric Taylor.
#
#   tclsh9.1 extras/listbench.tcl both              plain list and bitarray, side by side (the default)
#   tclsh9.1 extras/listbench.tcl l                 plain lists only: needs no extension at all, so anyone can run it
#   tclsh9.1 extras/listbench.tcl b                 bitarray only (1-bit and 8-bit columns)
#
# Options (after the mode):
#   -lib FILE       the extension to load for modes both and b (default: libbitarray.so / bitarray.dll in the current
#                   folder, next to this script or one folder up; or set BITARRAY_LIB)
#   -sizes A,B,C    array sizes (default 1000,100000,1000000)
#   -runs N         timing runs per operation; the best is reported (default 3)
#   -target MS      aim for about this many milliseconds per timing run (default 10)
#   -only PATTERN   only operations whose name matches PATTERN, ignoring case.  Plain text matches anywhere in the name
#                   (-only linsert); a pattern with * ? or [ ] is a glob and must match the whole name
#                   (-only "lre*", -only "*middle*").  Give -only more than once to add patterns.
#   -ratios         show only the two ratio columns (plain-list time divided by bitarray time), not the times; mode both only;
#                   rows that have no ratio (n/a in the full table) are left out
#   -sort KEY       list each table best to worst: best1 = by the plain/1bit ratio, best8 = by the plain/8bit ratio
#                   (rows with no ratio go last); mode both only
#   -md             print markdown tables instead of plain text
#   -verbose        print notes at the end on how to read the numbers (lazy lrange/lreverse, cold rows, memory estimate ...)
#   -nocheck        skip the check that every column gives the same answer
#   -quick          sizes 1000 and 100000, 2 runs
#   -help           print the usage (the same text is shown after any error); an unambiguous start of an option is enough
#
# It also times the extension's own fill, count and next, and its bitwise commands (and, or, xor, andnot, not: the rows named
# "bitop ..."), against helper procs for a plain list (fillList, countList, nextList, walkList, andList and so on, defined below; they are the fastest plain-Tcl way I know, so improve them if you know a faster one).
#
# What it measures: microseconds per call of one command, on the same data held as a plain list, as a 1-bit bitarray and as an
# 8-bit bitarray (every 7th element is 1, the rest 0).  Before timing, every operation is run once on 1000 elements in every
# column and the answers are compared (a benchmark of a wrong answer is worth nothing); a mismatch stops the run.
# In mode both the last two columns are plain-list time divided by bitarray time: above 1 the bitarray is faster, below 1 it
# is slower.  Notes printed at the end say what to keep in mind when reading the numbers.

set usageText {usage: tclsh9.1 listbench.tcl ?mode? ?options?

 mode   both   plain list and bitarray side by side (the default)
        l      plain lists only; needs no extension
        b      bitarray only (1-bit and 8-bit columns)

 options (an unambiguous start is enough, e.g. -ratio for -ratios)
  -lib FILE      the extension to load (modes both and b); default: libbitarray.so / bitarray.dll
                 in the current folder, next to this script or one folder up, or $BITARRAY_LIB
  -sizes A,B,C   array sizes (default 1000,100000,1000000)
  -runs N        timing runs per operation, the best is shown (default 3)
  -target MS     aim for about this many milliseconds per timing run (default 10)
  -only PATTERN  only operations whose name matches: plain text anywhere in the name, or a glob
                 ("lre*", "*middle*") that must match the whole name; can be repeated
  -ratios        show only the two ratio columns (mode both); rows with no ratio are left out
  -sort KEY      best1 or best8: order each table best to worst by that ratio (mode both)
  -md            markdown tables
  -verbose       print notes at the end on how to read the numbers
  -nocheck       skip the same-answer check
  -quick         sizes 1000 and 100000, 2 runs
  -help          this text

 examples
  tclsh9.1 listbench.tcl                               everything, plain list against bitarray
  tclsh9.1 listbench.tcl l                             plain lists only
  tclsh9.1 listbench.tcl both -ratios -sort best1      ratios only, biggest bitarray win first
  tclsh9.1 listbench.tcl both -only "linsert*" -quick  just the linsert rows, two sizes
  tclsh9.1 listbench.tcl both -only bitop -quick       just the and / or / xor / andnot / not rows ("-only 'bitop xor'" for one)}

proc die {msg} { puts stderr "listbench: $msg\n"; puts stderr $::usageText; exit 2 }

# ---- mode and options ----
set mode both; set sizes {1000 100000 1000000}; set runs 3; set targetMs 10; set only {}; set md 0; set check 1; set lib ""; set ratiosOnly 0; set sortKey ""; set verbose 0
set av $argv
if {[llength $av] && [string tolower [lindex $av 0]] in {help ? -h -help --help}} { puts $usageText; exit 0 }
if {[llength $av] && [string index [lindex $av 0] 0] ne "-"} {
    switch -- [string tolower [lindex $av 0]] {
	both - bl          { set mode both }
	b - bitarray       { set mode b }
	l - list - lists   { set mode l }
	default            { die "the mode must be both, b (bitarray) or l (plain list), not \"[lindex $av 0]\"" }
    }
    set av [lrange $av 1 end]
}
set knownOptions {-lib -sizes -runs -target -only -md -ratios -sort -verbose -nocheck -quick -help}
proc takeValue {name} {
    upvar 1 av av
    if {![llength $av]} { die "$name needs a value" }
    set v [lindex $av 0]; set av [lrange $av 1 end]
    return $v
}
while {[llength $av]} {
    set o [lindex $av 0]; set av [lrange $av 1 end]
    if {$o in {-h --help}} { set o -help }
    if {$o ni $knownOptions} {
	set m [lsearch -all -inline -glob $knownOptions $o*]
	if {[llength $m] == 1} { set o [lindex $m 0] } elseif {[llength $m] > 1} {
	    die "option $o is ambiguous: could be [join $m {, }]"
	} else { die "unknown option $o" }
    }
    switch -- $o {
	-lib     { set lib [takeValue $o] }
	-sizes   { set sizes [split [takeValue $o] ,] }
	-runs    { set runs [takeValue $o] }
	-target  { set targetMs [takeValue $o] }
	-only    { lappend only [string tolower [takeValue $o]] }
	-md      { set md 1 }
	-ratios  { set ratiosOnly 1 }
	-sort    { set sortKey [takeValue $o]
		   if {$sortKey ni {best1 best8}} { die "-sort takes best1 or best8, not \"$sortKey\"" } }
	-verbose { set verbose 1 }
	-nocheck { set check 0 }
	-quick   { set sizes {1000 100000}; set runs 2 }
	-help    { puts $usageText; exit 0 }
    }
}
foreach {n v} [list -runs $runs -target $targetMs] {
    if {![string is integer -strict $v] || $v < 1} { die "$n needs a whole number of 1 or more, not \"$v\"" }
}
foreach v $sizes {
    if {![string is integer -strict $v] || $v < 100} { die "-sizes takes whole numbers of 100 or more separated by commas, not \"$v\"" }
}
set types [dict get {both {plain w1 w8} b {w1 w8} l {plain}} $mode]
if {($ratiosOnly || $sortKey ne "") && $mode ne "both"} { die "-ratios and -sort compare the plain list with the bitarray, so they need mode both" }
set bav "(not loaded)"
if {$mode ne "l"} {
    if {$lib eq "" && [info exists ::env(BITARRAY_LIB)]} { set lib $::env(BITARRAY_LIB) }
    if {$lib eq ""} {
	set here [file dirname [file normalize [info script]]]
	foreach d [list [pwd] $here [file dirname $here]] {
	    foreach n {libbitarray bitarray} {
		set f [file join $d $n[info sharedlibextension]]
		if {[file exists $f]} { set lib $f; break }
	    }
	    if {$lib ne ""} break
	}
    }
    if {$lib eq ""} { die "cannot find the extension; use -lib FILE, set BITARRAY_LIB, or run with mode l to time plain lists only" }
    if {[catch {load $lib Bitarray} err]} { die "cannot load $lib: $err" }
    set bav [expr {[catch {bitarray version} v] ? "?" : $v}]
}

# ---- the operations ----
# Tokens in a script: @N size, @MID middle index, @MID9 middle+9, @MID99 middle+99, @HALF last index of the first half, @LAST last index,
# @H100 100 ones.
# Options: prep own  = start each timing run with a private copy of the array (needed when the command changes X);
#          prep share = X is the shared base array (read-only commands);
#          cold 1    = start from a fresh copy every run and call once: includes building the element objects the core asks
#                      for when it treats a bitarray as an ordinary list (the first call after any change);
#          reps N    = at most N calls per run (N may use @N, e.g. {@N/10});
#          s_plain / s_w1 / s_w8 = a different script for that column ({} = not applicable);
#          pre SCRIPT = run once after each preparation, outside the timing (lappend uses it to give the array its spare room,
#                       so that the cost of the first growth is not averaged into the figure);
#          data sparse = use an array of zeros whose only 1 is the last element (for searches that must scan a long way);
#          after SCRIPT = in the same-answer check, also compare what this script returns after the command (used to compare
#                       the array a fill has changed);
#          s_plain8  = plain-list script for the list / 8-bit ratio and the 8-bit same-answer check, when the operation differs from the 1-bit one;
#          z 1       = the script uses $Z, a second array of the same size and type as X (every 5th element 1);
#          noratio 1 = leave the ratio columns empty for this row (the comparison would mislead);
#          nocheck 1 = skip the same-answer check.
set OPS {}
proc op {name script args} {
    lappend ::OPS [dict merge {prep share reps 0 cold 0 nocheck 0 noratio 0 pre {} after {} data normal z 0} [list name $name script $script] $args]
}
op "create (lrepeat / bitarray new)" {} s_plain {lrepeat @N 0} s_w1 {bitarray new @N} s_w8 {bitarray new @N -width 8} nocheck 1
op "create from text (parse / newfrom)" {} s_plain {llength $S} s_w1 {bitarray newfrom $S} s_w8 {bitarray newfrom $S -width 8} nocheck 1 cold 1 pre {set S "$::STR "}
op "llength"                       {llength $X}
op "lindex (middle)"               {lindex $X @MID}
op "lset (middle, in place)"       {lset X @MID 1} prep own
op "lappend (one element)"         {lappend X 1} prep own reps 1000 pre {lappend X 1}
op "lrange 10..19"                 {lrange $X 10 19}
op "lrange first half"             {lrange $X 0 @HALF}
op "lreverse"                      {lreverse $X}
op "lreplace delete 100 at front"  {lreplace $X 0 99}
op "lreplace delete 100 in middle" {lreplace $X @MID @MID99}
op "lreplace 10 for 10 (middle)"   {lreplace $X @MID @MID9 1 1 1 1 1 1 1 1 1 1}
op "linsert 1 at front"            {linsert $X 0 1}
op "linsert 1 in middle"           {linsert $X @MID 1}
op "linsert 1 at end"              {linsert $X end 1}
op "linsert 100 in middle"         {linsert $X @MID @H100}
op "ledit 1 for 2 (shared: copies)" {set Y $X; ledit Y @MID @MID 1 1}
op "ledit 1 for 1 (in place)"      {ledit X @MID @MID 1} prep own
op "ledit delete 1 at front (in place)" {ledit X 0 0} prep own reps {@N/10}
op "lremove 3 elements"            {lremove $X 0 @MID end}
op "lassign 3 variables (of lrange)" {lassign [lrange $X @MID @MID+2] a b c}
op "lassign first 3 (rest returned)" {lassign $X a b c} cold 1
op "lsearch -exact (hit at 0, warm)" {lsearch -exact $X 1}
op "lsearch -exact (hit at 0, cold)" {lsearch -exact $X 1} cold 1
op "lsearch -exact (miss, scans all)" {lsearch -exact $X 2} cold 1
op "2 in \$X (miss)"               {expr {2 in $X}} cold 1 noratio 1
op "lsort -integer"                {lsort -integer $X} cold 1
op "foreach over all elements"     {foreach e $X {}} cold 1
op "lmap over all elements"        {lmap e $X {set e}} cold 1
op "join with a comma"             {join $X ,} cold 1

# ---- bitarray fill / count / next against what you would write for a plain list ----
# fillList, countList, nextList and walkList are the plain-list helpers; the bitarray columns call the extension directly.
proc fillList {var first last value {step 1}} {
    upvar 1 $var l
    if {$step == 1} {
	ledit l $first $last {*}[lrepeat [expr {$last - $first + 1}] $value]
    } else {
	for {set i $first} {$i <= $last} {incr i $step} { lset l $i $value }
    }
}
proc countList {l} { llength [lsearch -all -exact $l 1] }
proc nextList {l start} { lsearch -exact -start $start $l 1 }
proc walkList {l} {
    set c 0; set i [lsearch -exact $l 1]
    while {$i >= 0} { incr c; set i [lsearch -exact -start [expr {$i + 1}] $l 1] }
    return $c
}
proc walkBits {a} {
    set c 0; set i [bitarray next $a 0]
    while {$i >= 0} { incr c; set i [bitarray next $a [expr {$i + 1}]] }
    return $c
}
op "fill first half with 1 (no step)" {} s_plain {fillList X 0 @HALF 1} s_w1 {bitarray fill X 0 @HALF 1} s_w8 {bitarray fill X 0 @HALF 1} prep own after {set X}
op "fill every 3rd element with 1"  {} s_plain {fillList X 0 @LAST 1 3} s_w1 {bitarray fill X 0 @LAST 1 3} s_w8 {bitarray fill X 0 @LAST 1 3} prep own after {set X}
op "count the 1s"                   {} s_plain {countList $X} s_w1 {bitarray count $X} s_w8 {bitarray count $X}
op "next 1: one scan of the whole array" {} s_plain {nextList $X 0} s_w1 {bitarray next $X 0} s_w8 {bitarray next $X 0} data sparse
op "next 1: visit every 1 (every 7th)" {} s_plain {walkList $X} s_w1 {walkBits $X} s_w8 {walkBits $X}

# ---- bitwise operations on two arrays (bitarray 0.6.0): and, or, xor, andnot, not ----
# All five rows begin with "bitop", so  -only bitop  selects them together and  -only 'bitop xor'  or  -only 'bitop and *'  picks one.
# $Z is a second array of the same size (every 5th element 1, starting at 2; X has every 7th element 1).  The result goes into X, so the rows
# use a private copy.  The plain-list helpers are the usual one-line lmap loops.  "not" flips every bit, so on an 8-bit array 0 becomes
# 255 and 1 becomes 254: for the list / 8-bit ratio the plain list does the same (x ^ 255, notList8); the "list us" column and the
# list / 1-bit ratio use x ^ 1, the same operation on one bit.
proc andList    {var other} { upvar 1 $var l; set l [lmap x $l y $other {expr {$x & $y}}] }
proc orList     {var other} { upvar 1 $var l; set l [lmap x $l y $other {expr {$x | $y}}] }
proc xorList    {var other} { upvar 1 $var l; set l [lmap x $l y $other {expr {$x ^ $y}}] }
proc andnotList {var other} { upvar 1 $var l; set l [lmap x $l y $other {expr {$x & ~$y}}] }
proc notList    {var}       { upvar 1 $var l; set l [lmap x $l {expr {$x ^ 1}}] }
proc notList8   {var}       { upvar 1 $var l; set l [lmap x $l {expr {$x ^ 255}}] }
op "bitop and (a AND b)"        {} s_plain {andList X $Z}    s_w1 {bitarray and X $Z}    s_w8 {bitarray and X $Z}    prep own after {set X} z 1
op "bitop or (a OR b)"          {} s_plain {orList X $Z}     s_w1 {bitarray or X $Z}     s_w8 {bitarray or X $Z}     prep own after {set X} z 1
op "bitop xor (a XOR b)"        {} s_plain {xorList X $Z}    s_w1 {bitarray xor X $Z}    s_w8 {bitarray xor X $Z}    prep own after {set X} z 1
op "bitop andnot (a AND NOT b)" {} s_plain {andnotList X $Z} s_w1 {bitarray andnot X $Z} s_w8 {bitarray andnot X $Z} prep own after {set X} z 1
op "bitop not (flip every bit)" {} s_plain {notList X}       s_w1 {bitarray not X}       s_w8 {bitarray not X}       prep own after {set X} s_plain8 {notList8 X}

proc scriptFor {opd type n} {
    set key s_$type
    set s [expr {[dict exists $opd $key] ? [dict get $opd $key] : [dict get $opd script]}]
    set mid [expr {$n / 2}]
    set h100 [string repeat "1 " 99]1
    return [string map [list @N $n @MID99 [expr {$mid + 99}] @MID9 [expr {$mid + 9}] @MID $mid @HALF [expr {$n / 2 - 1}] @LAST [expr {$n - 1}] @H100 $h100] $s]
}
proc prep {kind {pre {}}} {
    if {$kind eq "own"} { set ::X $::BASE; lset ::X 0 [lindex $::BASE 0] } else { set ::X $::BASE }
    if {$pre ne ""} { uplevel #0 $pre }
}
proc measure {opd type n} {
    set script [scriptFor $opd $type $n]
    set cold [dict get $opd cold]
    set kind [expr {[dict get $opd prep] eq "own" || $cold ? "own" : "share"}]
    set cap [dict get $opd reps]
    if {$cap ne "0"} { set cap [expr [string map [list @N $n] $cap]] }
    if {$cold} {
	set reps 1
    } else {
	prep $kind [dict get $opd pre]
	set t1 [lindex [uplevel #0 [list time $script 1]] 0]
	set reps [expr {int($::targetMs * 1000.0 / ($t1 < 0.05 ? 0.05 : $t1))}]
	if {$reps < 1} { set reps 1 }
	if {$reps > 5000} { set reps 5000 }
	if {$cap ne "0" && $reps > $cap} { set reps [expr {$cap < 1 ? 1 : $cap}] }
    }
    set best 1e30
    for {set k 0} {$k < $::runs} {incr k} {
	if {$cold} {
	    # one fresh array per call, only the call is timed.  The clock has 1 microsecond resolution, so calls are repeated
	    # (each on a fresh array) until 2 ms of call time has been collected or 50 calls were made, and the mean is used.
	    set sum 0; set j 0
	    while {$j < 50 && ($j == 0 || $sum < 2000)} {
		prep $kind [dict get $opd pre]
		set c0 [clock microseconds]
		uplevel #0 $script
		incr sum [expr {[clock microseconds] - $c0}]
		incr j
	    }
	    set t [expr {double($sum) / $j}]
	} else {
	    prep $kind [dict get $opd pre]
	    set t [lindex [uplevel #0 [list time $script $reps]] 0]
	}
	if {$t < $best} { set best $t }
    }
    return $best
}
proc mklist2 {n} {
    set l [lrepeat $n 0]
    for {set i 2} {$i < $n} {incr i 5} { lset l $i 1 }
    return $l
}
proc setBase {type {sparse 0} {needZ 0}} {
    set src [expr {$sparse ? $::LS : $::L}]
    switch $type {
	plain - plain8 { set ::BASE $src }
	w1    { set ::BASE [bitarray newfrom $src] }
	w8    { set ::BASE [bitarray newfrom $src -width 8] }
    }
    if {$needZ} {
	if {![info exists ::L2] || [llength $::L2] != [llength $src]} { set ::L2 [mklist2 [llength $src]] }
	switch $type {
	    plain - plain8 { set ::Z $::L2 }
	    w1    { set ::Z [bitarray newfrom $::L2] }
	    w8    { set ::Z [bitarray newfrom $::L2 -width 8] }
	}
    }
}
proc mksparse {n} {
    set l [lrepeat $n 0]
    lset l end 1
    return $l
}
proc mklist {n} {
    set l [lrepeat $n 0]
    for {set i 0} {$i < $n} {incr i 7} { lset l $i 1 }
    return $l
}
proc wanted {name} {
    if {![llength $::only]} { return 1 }
    set lname [string tolower $name]
    foreach p $::only {
	if {[regexp {[*?\[\]]} $p]} {
	    if {[string match $p $lname]} { return 1 }
	} elseif {[string first $p $lname] >= 0} { return 1 }
    }
    return 0
}
proc applies {opd type} { expr {![dict exists $opd s_$type] || [dict get $opd s_$type] ne ""} }

# ---- check: same answers on 1000 elements, in every column that is being run ----
# An operation is compared in every column that has a script for it (its own script, or an s_plain / s_w1 / s_w8 one).  A row with
# s_plain8 (the plain-list version of an operation that behaves differently at 8 bits, such as not) is checked against that in the 8-bit column.
proc checkRun {opd type} {
    setBase $type [expr {[dict get $opd data] eq "sparse"}] [dict get $opd z]
    prep own
    set r [uplevel #0 [scriptFor $opd $type 1000]]
    if {[dict get $opd after] ne ""} { set r [uplevel #0 [dict get $opd after]] }
    return "$r"
}
if {$check && [llength $types] > 1} {
    set ::L [mklist 1000]; set ::LS [mksparse 1000]
    set nchecked 0; set nskipped 0
    foreach opd $OPS {
	if {[dict get $opd nocheck]} { incr nskipped; continue }
	set ref ""; set first 1
	foreach type $types {
	    if {![applies $opd $type] || ![string length [scriptFor $opd $type 1000]]} continue
	    set r [checkRun $opd $type]
	    if {$type eq "w8" && [dict exists $opd s_plain8]} {
		set r8 [checkRun $opd plain8]
		if {$r ne $r8} {
		    die "answers differ for \"[dict get $opd name]\" (w8 against the 8-bit plain list): [string range $r 0 60] ... against [string range $r8 0 60] ..."
		}
		continue
	    }
	    if {$first} { set ref $r; set first 0 } elseif {$r ne $ref} {
		die "answers differ for \"[dict get $opd name]\" ($type): [string range $r 0 60] ... against [string range $ref 0 60] ..."
	    }
	}
	incr nchecked
    }
    puts "check: $nchecked operations compared, same answers in every column ($nskipped not comparable: creation and parsing)"
}

# ---- machine-speed calibration: an empty loop of 1,000,000 iterations (byte-compiled inside a proc), best of 5 ----
proc emptyLoop {} { for {set i 0} {$i < 1000000} {incr i} {} }
proc calibrate {} {
    set best 1e30
    for {set k 0} {$k < 5} {incr k} {
	set t [lindex [time {emptyLoop}] 0]
	if {$t < $best} { set best $t }
    }
    return [format "empty loop of 1,000,000 iterations %.1f ms (best of 5)" [expr {$best / 1000.0}]]
}

# ---- memory saving, estimated for the array itself (not measured; performance_analysis.md section 2 has measured figures) ----
proc memorySaving {n} {
    set list [expr {8 * $n}]                      ;# one 8-byte pointer per element (the 0 and 1 objects are shared)
    set b1 [expr {8 * (($n + 63) / 64)}]          ;# 64 elements per 8-byte word
    set b8 $n                                     ;# one byte per element
    return [format "%.0fx/%.0fx" [expr {$list / double($b1)}] [expr {$list / double($b8)}]]
}

# ---- formatting ----
proc commas {x} {
    set s [format %.0f $x]
    while {[regsub {^(-?\d+)(\d{3})} $s {\1,\2} s]} {}
    return $s
}
proc fmt {us} { if {$us < 10} { format %.2f $us } elseif {$us < 100} { format %.1f $us } else { commas $us } }
proc ratioNum {a b} {
    if {$a eq "-" || $b eq "-" || $b <= 0} { return "" }
    return [expr {$a / $b}]
}
proc ratioText {r} {
    if {$r eq ""} { return "" }
    return [expr {$r >= 10 ? [format %.0fx $r] : $r >= 1 ? [format %.1fx $r] : $r >= 0.01 ? [format %.2fx $r] : "<0.01x"}]
}
set label [dict create plain "list us" w1 "bit1 us" w8 "bit8 us"]
set ratios [expr {$mode eq "both"}]
set heads {}; foreach t $types { lappend heads [dict get $label $t] }
if {$ratios} { lappend heads "list/bit1" "list/bit8" }
if {$ratiosOnly} { set heads {list/bit1 list/bit8} }

puts "listbench ($mode): Tcl [info patchlevel], bitarray $bav, $::tcl_platform(machine) $::tcl_platform(os), [clock format [clock seconds] -format %Y-%m-%d]"
if {$mode ne "l"} {
    puts "[string repeat - 30] bench: $bav [clock format [file mtime $lib] -format {%Y-%m-%d %H:%M:%S}] [string repeat - 15]"
    puts "library $lib"
}
puts "calibration: [calibrate]"
set t0 [clock seconds]
foreach n $sizes {
    set ::L [mklist $n]; set ::LS [mksparse $n]; set ::STR [join $::L " "]
    puts ""
    set title "$n elements: "
    append title [expr {$ratiosOnly ? "time list/bitarray (>1x: bitarray faster)" : "us per call, best of $runs"}]
    if {$sortKey ne ""} { append title ", sorted by [expr {$sortKey eq {best1} ? {bit1} : {bit8}}]" }
    if {$mode eq "both"} { append title "; memory [memorySaving $n] less" }
    if {$md} {
	puts "### $title\n"
	puts "| operation | [join $heads { | }] |"
	puts "|---|[string repeat ---| [llength $heads]]"
    } else {
	puts $title
	puts [format "%-36s%s" operation [join [lmap h $heads {format " %10s" $h}] ""]]
    }
    set rows {}
    foreach opd $OPS {
	set name [dict get $opd name]
	if {![wanted $name]} continue
	set res {}; set any 0
	foreach type $types {
	    if {![applies $opd $type]} { lappend res - ; continue }
	    set any 1
	    setBase $type [expr {[dict get $opd data] eq "sparse"}] [dict get $opd z]
	    lappend res [measure $opd $type $n]
	}
	if {!$any} continue
	# a row with s_plain8: the list / 8-bit ratio is against the plain list doing the 8-bit version of the operation
	set p8 ""
	if {[dict exists $opd s_plain8] && "plain" in $types && "w8" in $types} {
	    setBase plain8 [expr {[dict get $opd data] eq "sparse"}] [dict get $opd z]
	    set p8 [measure $opd plain8 $n]
	}
	set cells {}; foreach v $res { lappend cells [expr {$v eq "-" ? "-" : [fmt $v]}] }
	set r1 ""; set r8 ""
	if {$ratios && ![dict get $opd noratio]} {
	    lassign $res p b1 b8
	    set r1 [ratioNum $p $b1]; set r8 [ratioNum [expr {$p8 ne "" ? $p8 : $p}] $b8]
	}
	# a row with no ratio (newfrom has no plain-list counterpart; "2 in" is not comparable) shows n/a, and is left out of -ratios
	if {$ratiosOnly && $r1 eq "" && $r8 eq ""} continue
	if {$ratios} { lappend cells [expr {$r1 eq "" ? "n/a" : [ratioText $r1]}] [expr {$r8 eq "" ? "n/a" : [ratioText $r8]}] }
	if {$ratiosOnly} { set cells [lrange $cells end-1 end] }
	set key [expr {$sortKey eq "best1" ? $r1 : $sortKey eq "best8" ? $r8 : ""}]
	lappend rows [list $name $cells [expr {$key eq "" ? -1.0 : double($key)}]]
    }
    if {$sortKey ne ""} { set rows [lsort -real -decreasing -index 2 $rows] }
    foreach row $rows {
	lassign $row name cells
	if {$md} {
	    puts "| $name | [join $cells { | }] |"
	} else {
	    puts [format "%-36s%s" $name [join [lmap c $cells {format " %10s" $c}] ""]]
	}
    }
    unset ::L ::LS ::STR ::BASE ::X
    catch {unset ::S}
    catch {unset ::Y}
    catch {unset ::L2}
    catch {unset ::Z}
}
puts ""
if {$verbose} {
    puts "notes:"
    puts " * 'memory 64x/8x less' in each title (bit1 first, then bit8) is an estimate for the array itself, list size divided by bitarray size: a list holds"
    puts "   an 8-byte pointer per element (this test data shares one object each for 0 and 1), a 1-bit array 1 bit, an 8-bit array 1 byte."
    puts "   A list of distinct numbers also needs one 48-byte object per element, about 56 bytes each, so the saving would be larger."
    puts " * One machine, one run of the program; the same command often varies by 30% between runs.  Treat differences under about 2x as noise."
    puts " * lrange and lreverse on a plain list are lazy in Tcl 9.1 (a shared slice, a reversed view), so they cost almost nothing until the"
    puts "   result is used; a bitarray makes a real copy.  See performance_analysis.md section 2."
    puts " * 'cold' rows start from a fresh array for every call and time only the call.  For a bitarray they include building the list of"
    puts "   element objects that the core asks for when a command treats it as an ordinary list; that list is kept until the array is next"
    puts "   changed, so a second call on the same unchanged array is faster ('warm')."
    puts " * '2 in \$X (miss)': a bitarray answers at once for a value it cannot hold; a plain list has to look at every element."
    puts " * 'ledit (shared: copies)' is what a loop sees when another variable holds the same value; 'in place' is the unshared case."
    puts " * lappend, lset and the in-place ledit rows work on a private copy and repeat the call; lappend is amortised (the array doubles)."
    puts " * 'create from text': both start from the same fresh string of values.  The plain list is made by parsing it (llength forces the"
    puts "   string to become a list); newfrom parses it the same way and then also range-checks and packs every element.  Assigning an"
    puts "   existing list (set a \$L) just shares it and costs almost nothing, so that is not a fair comparison."
    puts " * lassign: the first row is the usual use (take a few elements, here from the middle, into variables). The second names three
   variables for the first three elements of the whole array and returns the rest as its result; the core skips building that
   rest when the result is unused (a loop or proc body), so the row shows only the cost when it is used, which is rare.
 * lrepeat is also lazy in Tcl 9.1 (a repeated-list view), which is why plain 'create' is so cheap."
} else {
    puts "(add -verbose for notes on how to read these numbers)"
}
puts "elapsed [expr {[clock seconds] - $t0}] seconds"
puts "calibration at the end: [calibrate]  (a big difference from the start means the machine was busy)"
