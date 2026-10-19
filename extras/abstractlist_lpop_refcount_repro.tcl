# lpop with an index on the core's abstract list [lstring] (tcltest shell, built with TCL_MEM_DEBUG) leaves the object with one
# reference too few.  The object's refcount, seen through [tcl::unsupported::representation], after [lset] and after [lpop]:
proc rc {v} { regexp {refcount of (\d+)} [tcl::unsupported::representation $v] -> n; set n }
set b [lstring abcdef]; lset b 1 X;  puts "after lset b 1 X : refcount [rc $b]"
set b [lstring abcdef]; lpop b 1;    puts "after lpop b 1   : refcount [rc $b]"
# and a script that ends with "alloc: invalid block" in a TCL_MEM_DEBUG build:
proc show {script} { uplevel 1 $script }
set b [lstring abcdef]
show {list [lpop b 1] $b}
puts "before the assignment"
set b 0
puts "not reached"
