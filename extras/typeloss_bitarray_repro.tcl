# Which core list commands keep a bitarray a bitarray, and which turn it into a plain list.
# Usage:  tclsh9.1 bitarray_typeloss_repro.tcl /path/to/libbitarray.so
load [lindex $argv 0] Bitarray
proc type {v} { lindex [tcl::unsupported::representation $v] 3 }
proc mk {} { bitarray new 100 1 }

proc compiled {} {            ;# bytecode-compiled, local variables
    set b [mk]; set c [linsert $b end 1];   puts "linsert end 1 elem   compiled (INST_LREPLACE)      : [type $c]"
    set b [mk]; lappend b 1;                puts "lappend 1 elem        compiled in a proc            : [type $b]"
    set b [mk]; lappend b 1 0;              puts "lappend 2 elems       compiled in a proc            : [type $b]"
}
proc interpreted {} {         ;# command name in a variable => not compiled => Tcl_*ObjCmd run directly
    set li linsert; set la lappend
    set b [mk]; set c [$li $b end 1];       puts "linsert end 1 elem    NOT compiled (Tcl_LinsertObjCmd): [type $c]"
    set b [mk]; set c [$li $b end 1 0];     puts "linsert end 2 elems   NOT compiled                  : [type $c]"
    set b [mk]; set c [$li $b 5 1];         puts "linsert middle        NOT compiled                  : [type $c]"
    set b [mk]; $la b 1;                    puts "lappend 1 elem        NOT compiled (Tcl_LappendObjCmd): [type $b]"
}
compiled; interpreted
