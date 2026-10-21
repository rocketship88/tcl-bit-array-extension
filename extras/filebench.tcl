# filebench.tcl -- the file and text conversions of performance_analysis.md, section 4.
#   usage:  tclsh extras/filebench.tcl ROUTE      (set BITARRAY_LIB=/full/path/libbitarray.so if it is not in the current directory)
#   ROUTE is one of: frombytes scanroute splitroute tobytes formatroute fromchars tochars textscan textformat
# One route per process, so that the peak memory it prints (Linux only: VmHWM from /proc) is that route's own.  The table in the
# document is the median of three runs of each route.
load [expr {[info exists ::env(BITARRAY_LIB)] ? $::env(BITARRAY_LIB) : [file join [pwd] libbitarray.so]}] Bitarray
proc hwm {} {if {[catch {set f [open /proc/self/status]; set s [read $f]; close $f; regexp {VmHWM:\s+(\d+)} $s -> k}]} {return 0}; expr {$k/1024.0}}
set data [string range [string repeat [binary format cu* [lseq 0 255]] 4100] 0 1039999]
set text [string repeat "Hello, wörld! " 74286]; set text [string range $text 0 1039999]
set a [bitarray frombytes $data]
set route [lindex $argv 0]
set b16 [bitarray fromchars $text -width 16]
set base [hwm]
set t [lindex [time {
switch $route {
 frombytes   {set r [bitarray frombytes $data]}
 scanroute   {binary scan $data cu* l; set r [bitarray newfrom $l -width 8]}
 splitroute  {set l {}; foreach ch [split $data ""] {lappend l [scan $ch %c]}; set r [bitarray newfrom $l -width 8]}
 tobytes     {set r [bitarray tobytes $a]}
 formatroute {set r [binary format cu* $a]}
 fromchars   {set r [bitarray fromchars $text -width 16]}
 tochars     {set r [bitarray tochars $b16]}
 textscan   {set l [lmap ch [split $text ""] {scan $ch %c}]; set r [bitarray newfrom $l -width 16]}
 textformat {set r [join [lmap n $b16 {format %c $n}] ""]}
}} 1] 0]
puts [format "%-12s %10.0f us   +%.0f MB peak" $route $t [expr {[hwm]-$base}]]
