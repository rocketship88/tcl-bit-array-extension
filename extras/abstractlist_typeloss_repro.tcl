# Which operations turn an abstract list into an ordinary list (tcltest shell, [lstring]); the values are all correct.
proc type {v} { lindex [tcl::unsupported::representation $v] 3 }
set e [lstring abcdef]; set l [list $e y]; lset l 0 1 Z
puts "nested lset into an element        : [lindex $l 0] / [type [lindex $l 0]]"
set d [dict create k [lstring abcdef]]; dict lappend d k Z
puts "dict lappend onto a dict value     : [dict get $d k] / [type [dict get $d k]]"
set li linsert; set b [lstring abcdef]; set c [$li $b end z]
puts "linsert end, not bytecode-compiled : [type $c]"
set b [lstring abcdef]; lappend b z
puts "lappend (global level, see ticket 0c82728f85) : [type $b]"
proc f {} { set b [lstring abcdef]; lappend b z; type $b }
puts "lappend in a proc                  : [f]"
