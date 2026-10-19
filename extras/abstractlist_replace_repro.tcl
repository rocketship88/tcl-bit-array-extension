# Calls the public Tcl_ListObjReplace(first, count, 0 new elements) on an ordinary list and on the core's own abstract list
# [lstring] (it has a Replace hook).  Needs the tcltest shell (it has [lstring]) and the probe in abstractlist_replprobe.c:
#   gcc -fPIC -shared -DUSE_TCL_STUBS -I TCLSRC/generic abstractlist_replprobe.c TCLBUILD/libtclstub.a -o libreplprobe.so
#   ./tcltest abstractlist_replace_repro.tcl
load ./libreplprobe.so Replprobe
puts "first count : ordinary list a..f -> {length string}   |   lstring abcdef -> {length string}"
foreach {f c} {1 2  -3 2  3 99  99 1  2 -5} {
    puts [format "%5d %5d : %-24s | %s" $f $c [replprobe plain $f $c] [replprobe lstring $f $c]]
}
