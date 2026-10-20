# op_examples.tcl -- five small uses of bitarray op (comparisons and logical operators), each with sample data and an explanation.
# Written by Claude (an AI model made by Anthropic) for Eric Taylor.  Run it (tclsh or wish) from the folder holding the extension, or paste a block into a console.

package require bitarray
# ---- 1: which readings are too hot? (a threshold mask) ----
set temps [bitarray newfrom {72 75 81 90 78 85 70 82} -width 8]
bitarray op hot = $temps > 80
puts "temperatures : $temps"
puts "hot (> 80)   : $hot"
puts "how many hot : [bitarray count $hot]"
puts "first hot at index [bitarray next $hot 0 1]"
set i [bitarray next $hot 0 1]
while {$i >= 0} {
    puts "  index $i has [lindex $temps $i]"
    set i [bitarray next $hot [expr {$i + 1}] 1]
}
# ---- 2: are all values within limits, and where is the first bad one? ----
set v [bitarray newfrom {12 18 25 10 20 7 15 20} -width 8]
bitarray op ok = [bitarray op $v >= 10] and [bitarray op $v <= 20]
puts "values       : $v"
puts "in 10..20    : $ok"
puts [expr {0 ni $ok ? "all values are in range" : "some values are out of range"}]
puts "first bad index : [bitarray next $ok 0 0]   (-1 would mean none)"
puts "bad values      : [expr {[llength $ok] - [bitarray count $ok]}]"
set v2 [bitarray newfrom {12 18 20 10 11} -width 8]
bitarray op ok2 = [bitarray op $v2 >= 10] and [bitarray op $v2 <= 20]
puts [expr {0 ni $ok2 ? "second list: all in range" : "second list: some out of range"}]
# ---- 3: what changed between two snapshots? ----
set before [bitarray newfrom {1 0 0 1 1 0 1 0}]
set after  [bitarray newfrom {1 0 1 1 0 0 1 1}]
bitarray op changed = $before != $after
puts "before  : $before"
puts "after   : $after"
puts "changed : $changed"
puts "[bitarray count $changed] elements differ"
puts [expr {1 in $changed ? "something changed" : "nothing changed"}]
set i [bitarray next $changed 0 1]
while {$i >= 0} {
    puts "  index $i: [lindex $before $i] -> [lindex $after $i]"
    set i [bitarray next $changed [expr {$i + 1}] 1]
}
# ---- 4: a 1-bit validity array combined with wide data ----
set values [bitarray newfrom {0 250 0 7 1000 0} -width 16]
set valid  [bitarray newfrom {1 1 0 1 0 1}]
bitarray op big = $values > 100
bitarray op use = $valid && $big
puts "values : $values   (16-bit)"
puts "valid  : $valid   (1-bit)"
puts "big    : $big   (values > 100)"
puts "use    : $use   (valid and big)"
puts "nonzero and valid : [bitarray op $values && $valid]"
# ---- 5: one step of a cellular automaton (game of life rules) ----
set alive  [bitarray newfrom {1 0 1 1 0 1 0 1}]
set counts [bitarray newfrom {2 3 3 1 3 4 0 3} -width 8]
bitarray op born = [bitarray op $alive == 0] and [bitarray op $counts == 3]
bitarray op stay = $alive and [bitarray op [bitarray op $counts == 2] or [bitarray op $counts == 3]]
bitarray op next = $born or $stay
puts "alive now   : $alive"
puts "neighbours  : $counts"
puts "born        : $born"
puts "survive     : $stay"
puts "next gen    : $next"
