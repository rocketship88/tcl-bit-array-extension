# procs_only.tcl -- copy Frank's sieve file without its top-level "main ..." calls, so sourcing it does not start its own
# 5-second loop.  Used by ../run_sieves.bat (the Unix script does the same with grep).
#   tclsh procs_only.tcl INPUT OUTPUT
# The same rule as the Unix script: drop every line that begins with "main" followed by white space or the end of the line.
# Exits with status 1 and a message if INPUT does not define "proc run_sieve".
lassign $argv in out
if {$in eq "" || $out eq ""} { puts stderr "usage: tclsh procs_only.tcl INPUT OUTPUT"; exit 2 }
set f [open $in rb]; set data [read $f]; close $f
set keep {}; set def 0
foreach line [split $data \n] {
    set l [string trimright $line \r]
    if {[regexp {^\s*proc\s+run_sieve\s} $l]} { set def 1 }
    if {[regexp {^main(\s|$)} $l]} continue
    lappend keep $l
}
if {!$def} { puts stderr "$in does not define 'proc run_sieve'"; exit 1 }
set f [open $out w]; fconfigure $f -translation lf; puts -nonewline $f [join $keep \n]; close $f
