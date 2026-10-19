# pkgIndex.tcl -- lets "package require bitarray" find the extension.
# Tcl sets $dir to the directory holding this file when it reads it, so keep this file
# and the built library (libbitarray.so, or bitarray.dll on Windows) together in one directory.
if {![package vsatisfies [package provide Tcl] 9.1-]} {return}
package ifneeded bitarray 0.8.5 [list load [file join $dir [expr {$::tcl_platform(platform) eq "windows" ? "bitarray" : "libbitarray"}][info sharedlibextension]] Bitarray]
