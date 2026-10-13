# Memory growth check for the element cache of wide arrays (Linux: reads /proc/self/status).
# Builds and drops arrays of 300,000 distinct values, with the element cache built, at every width, and
# leaves the resident size in ::leakGrowthMB (growth between round 2 and round 6).  A leak of the cached
# element objects shows up as hundreds of MB; a clean run stays within a few MB.
proc rss {} { set f [open /proc/self/status]; set d [read $f]; close $f; regexp {VmRSS:\s+(\d+) kB} $d -> kb; expr {$kb/1024.0} }
set L {}; for {set i 0} {$i < 300000} {incr i} {lappend L [expr {$i*1000003 - 150000000000}]}
for {set round 0} {$round < 6} {incr round} {
    foreach w {8 16 32 64} {
        set src [expr {$w==64 ? $L : [lmap x $L {expr {$x % ((1<<$w)-1)}}]}]
        set a [bitarray newfrom $src -width $w]
        set s [lsort -integer $a]          ;# builds the element cache of fresh objects
        lset a 5 7                          ;# drops the cache
        set s [lsort -integer $a]
        lappend a 3; set a [lrange $a 1 100000]; set s [lsort -integer $a]
        unset a s
    }
    if {$round == 1} { set r1 [rss] }
    if {$round == 5} { set r5 [rss] }
}
set ::leakGrowthMB [expr {$r5 - $r1}]
