# Reproduction with stock Tcl only: needs a tcltest shell (test commands built in), which provides [lstring].
# [lstring] makes an abstract list that HAS a Replace hook.   Usage: tcltest lstring_repro.tcl
proc type {v} { lindex [tcl::unsupported::representation $v] 3 }
proc mk {} { lstring abcdef }
proc compiled {} {
    set b [mk]; set c [linsert $b end z];  puts "linsert end 1 elem  compiled (INST_LREPLACE)     : [type $c]"
    set b [mk]; lappend b z;               puts "lappend 1 elem       compiled in a proc           : [type $b]"
    set b [mk]; lappend b y z;             puts "lappend 2 elems      compiled in a proc           : [type $b]"
}
proc interpreted {} {   ;# command name in a variable => not compiled => the Tcl_*ObjCmd functions run directly
    set li linsert; set la lappend
    set b [mk]; set c [$li $b end z];      puts "linsert end 1 elem   NOT compiled (Tcl_LinsertObjCmd): [type $c]"
    set b [mk]; set c [$li $b end y z];    puts "linsert end 2 elems  NOT compiled                  : [type $c]"
    set b [mk]; set c [$li $b 2 z];        puts "linsert middle       NOT compiled                  : [type $c]"
    set b [mk]; $la b z;                   puts "lappend 1 elem       NOT compiled (Tcl_LappendObjCmd): [type $b]"
}
compiled; interpreted
