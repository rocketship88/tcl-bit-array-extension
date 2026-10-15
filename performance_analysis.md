# bitarray: why it exists, what it costs, when to use it

Version 0.6.0, Tcl 9.1. The figures were measured with 0.5; the only ones measured again since are the two 1-bit edit rows in section 3 (after the 0.5.1 change) and the bitwise rows in section 4 (0.6.0). Written by Eric Taylor together with Claude (Anthropic's AI model), which ran the measurements and
drafted the text. Every figure below was measured on the machines named in each section; nothing is estimated unless it says so.

## 1. Why bitarray

Tcl 9.1 lets an extension supply its own list representation (abstract lists). `bitarray` is an extension that uses it to
store large arrays of small integers packed (1, 8, 16, 32 or 64 bits per element) while still being a Tcl list: `lindex`,
`lset`, `lrange`, `foreach`, `lsearch` and the rest work on it unchanged. It adds a few commands for work that a list
cannot do quickly: `fill`, `count`, `next`, the bitwise commands `and`, `or`, `xor`, `andnot` and `not`, and four conversions between arrays and files or text.

The aim is to show that the abstract-list hooks are enough for a useful, fast data type outside the core, and to give
programs that need large arrays of flags or bytes something much smaller and faster than a list of separate numbers.

## 2. Memory

One million elements. Each case ran in a fresh process; resident memory read from Linux (one run, about 0.05 MB accuracy).

| | plain list | bitarray 1-bit | bitarray 8-bit |
|---|---|---|---|
| the array itself | 7.9 MB | 0.12 MB | 1.0 MB |

The plain list in that row has every element sharing the same small-number object, which is the best case for a list. A list
of one million separate integers (values 0..255) takes 55 MB. So a bitarray is about 63x (1-bit) and 7.6x (8-bit) smaller
than the best-case list, and about 440x and 53x smaller than a list of separate integers.

Extra memory an operation needs, with the original kept as well:

| operation | plain list | bitarray 1-bit | bitarray 8-bit |
|---|---|---|---|
| `lrange` half the array | 0 | 0.06 MB | 0.5 MB |
| `lreverse` | 0 | 0.12 MB | 1.0 MB |
| `lreplace` (delete 1000 elements) | 7.8 MB | 0.12 MB | 1.0 MB |
| `linsert` (one element, middle) | 7.8 MB | 0.32 MB | 2.0 MB |
| `lappend` (one element, shared copy) | 7.8 MB | 0.32 MB | 2.0 MB |

A plain list copies a pointer for every element on each edit; a bitarray copies only its packed data. The plain-list zeros
are because Tcl 9.1 makes `lrange` a shared slice and `lreverse` a lazy view (its internal type is `reversedList`); the
bitarray versions make real copies. The `linsert` and `lappend` rows are about double the array size on purpose: the
allocation doubles when it grows so that repeated appends stay fast.

## 3. Speed of the list commands

One million elements, microseconds per call (best of five runs), Tcl 9.1.1 on Linux, one machine.

| operation | plain list | bitarray 1-bit | bitarray 8-bit |
|---|---|---|---|
| `lindex`, `lset`, `lappend` (one), `llength`, `lsearch` (hit at start) | 0.3 to 0.4 | same | same |
| `lrange` 10..19 | 0.33 | 0.39 | 0.38 |
| `lrange` half the array | 0.30 | 2.8 | 18.7 |
| `lreverse` | 0.40 | 1,156 | 1,805 |
| `lreplace` (delete 1000 near the start) | 3,872 | 57 | 75 |
| `linsert` (one element in the middle) | 4,136 | 33 | 139 |
| `foreach` over the whole array | 114,120 | 117,361 | 115,633 |

- Reading and writing single elements, searching and `foreach` cost the same as with a plain list.
- Edits are faster: about 52x (`lreplace`) and 30x (`linsert`) for 8-bit data, and about 68x and 125x for 1-bit. Before 0.5.1 the 1-bit figures were 2,139 and 1,153 µs (only 2x and 4x faster than a plain list), because the part of the array after the edit was moved one bit at a time; it is now moved 64 bits at a time. Timings in this container vary by about 30% from run to run.
- Large slices and reversals favour the core: a plain `lrange` and `lreverse` do no copying (see section 2). Once you
  use the elements the difference vanishes: running through every element of a reversed array took about 122 ms (1-bit),
  145 ms (8-bit) and 125 ms (plain list). The 1 to 2 ms `lreverse` is slower than a plain memory copy of that size
  should be, so it can probably be improved; that has not been looked at.

## 4. Where the large gains are: the bulk commands and files

These have no plain-list equivalent, so the comparison is against the best list code that does the same job.

**Sieve of Eratosthenes** (primes to 1,000,000; Frank van Bakel's Tcl entry from Dave's Garage as the plain-list baseline):

| variant | what it is | speed against the plain-list sieve |
|---|---|---|
| C | bitarray, but `lindex`/`lset` per bit (no bulk commands) | about 8x (7.7 to 9.4) |
| D | bitarray with `fill` (step) and `next` | about 410x to 620x |
| F | same, 8-bit elements | about 510x to 780x |

The ranges come from all stored runs on Linux and on two Windows 10 machines. On the faster Windows machine (i7-12700K): plain list
423,724 µs, variant D 688 µs, variant F 544 µs. On the slower one: 670,911, 1,204 and 1,222 µs.

**Files and text** (a 1,040,000-byte file, Linux, one run each):

| job | bitarray | the usual way |
|---|---|---|
| file to 8-bit array | `frombytes` 543 µs | `binary scan cu*` plus `newfrom` 42,326 µs; `split` plus `scan %c` 648,298 µs and 171 MB |
| 8-bit array to bytes | `tobytes` 542 µs | `binary format cu*` 44,699 µs and 58 MB |
| text to array | `fromchars` 12,915 µs | |
| array to text | `tochars` 7,380 µs | |

**Bitwise operations** (0.6.0; `extras/listbench.tcl -only 'bitop*'`, Linux, idle machine, microseconds per call, best of three; the result goes into the first array; the plain-list side is the one-line loop `set l [lmap x $l y $o {expr {$x & $y}}]`, and `extras/listbench_output_linux.txt` has the other rows):

| elements | operation | plain list | 1-bit | 8-bit | list / 1-bit | list / 8-bit |
|---|---|---|---|---|---|---|
| 1,000 | `and` | 70.0 | 0.23 | 0.27 | 304x | 256x |
| 100,000 | `and` | 6,041 | 0.68 | 5.53 | 8,912x | 1,092x |
| 1,000,000 | `and` | 74,248 | 8.15 | 57.7 | 9,109x | 1,286x |
| 1,000,000 | `or` | 52,974 | 6.55 | 89.9 | 8,086x | 589x |
| 1,000,000 | `xor` | 50,034 | 5.22 | 52.8 | 9,591x | 948x |
| 1,000,000 | `andnot` | 68,068 | 7.7 | 85.8 | 8,842x | 794x |
| 1,000,000 | `not` | 53,665 | 5.26 | 40.2 | 10,212x | 1,330x |

All five rows at the three sizes are in the saved benchmark output, and the benchmark first checks, on 1,000 elements, that the plain-list loop and both bitarray columns give the same answers. A 1-bit array does a million elements in about 15,600 word operations; an 8-bit array is eight times as large and took about 7 to 14 times as long here (57.7 against 8.15 µs for `and`, 89.9 against 6.55 for `or`). `not` flips every bit, so on an 8-bit array 0 becomes 255; its 8-bit ratio is against a plain-list loop doing `x ^ 255`. Timings in this container vary by about 30% from run to run, and so do the ratios, because the plain-list time moves too.

## 5. What it does differently from a list

- Elements must be integers that fit the width; anything else is an error (`expected integer in range 0..255 but got
  "abc"`). A plain list would accept it. This is deliberate and is the main difference.
- Width 64 is signed (-2^63 to 2^63-1); there is no unsigned 64-bit.
- `lappend` compiled inside a proc turns the bitarray into an ordinary list with the same values; at global level it keeps the
  type. `linsert` of exactly one element at the end loses the type when it is not bytecode-compiled. The core converts the
  value before the extension is called, so the extension cannot prevent it. It is a core ticket:
  https://core.tcl-lang.org/tcl/tktview/0c82728f85760f36361fe42a15f55453c94d285d
- `lsort`, `lsearch -all`, `lmap`, `split`, `concat`, `lrepeat`, `lseq` and `list {*}$a` return plain lists (the values are right).
  `lrange`, `lreplace`, `linsert`, `lreverse`, `lset`, `ledit`, `lremove` and `lassign` keep the type and width.

## 6. When to use which

| situation | use |
|---|---|
| Large arrays of small integers or flags (sieves, bitmaps, counters, byte buffers) | bitarray: 8x to 440x less memory |
| Bulk work: set a range, count, find the next | bitarray (`fill`, `count`, `next`) |
| Combining two big arrays of flags or bytes (union, intersection, difference, flip) | bitarray (`or`, `and`, `andnot`, `xor`, `not`): thousands of times faster than a loop |
| Reading or writing a file as bytes or text | bitarray (`frombytes`, `tobytes`, `fromchars`, `tochars`) |
| Many edits in the middle of a big array | bitarray: much less copying |
| Looking at single elements, searching, `foreach` | either: same speed |
| Elements that are not all integers that fit (strings, floats, nested lists, mixed) | plain list |
| Small arrays (tens or hundreds of elements) | plain list: savings are tiny and no extension is needed |
| Large slices or reversals where little of the result is used | plain list: lazy views cost nothing |
| Must run on a Tcl older than 9.1, or without a compiled extension | plain list |
| Results of `lsort`, `lmap`, `split` | plain list (the result is one; use `newfrom` to pack it again) |

## 7. Questions a reviewer may ask

1. **Why not a byte array / `binary`?** A byte array is not a list: no element `lindex`/`lset`, no `foreach`, no widths other
   than bytes. The `binary` commands are the slow route to it (section 4). See Appendix 1 for what a byte array is.
2. **Why not a dict or an array with integer keys?** They use far more memory per element and have no bulk commands. Not
   benchmarked here; the plain-list sieve is the comparison that was measured.
3. **Does it break code that expects lists?** Everything that accepts a list accepts it. The 251 tests, and random
   comparisons against plain lists (values and error text), check that results equal a list's apart from the intended errors.
4. **What about threads and shared values?** Values are immutable and copy on write like any Tcl value. Threads have not been
   tested.
5. **Why not in the core?** It needs only the abstract-list hooks, which is the point: they are enough for an extension.
   A core version could also make `lrange` and `lreverse` lazy like the core's own lists.

## 8. What was not tested

32-bit builds, Visual Studio versions other than 2022, macOS, big-endian machines, threads, Tcl 9.0.x. `ledit`, `lremove` and
`lassign` are tested in the suite since 0.5.1. The speed and memory figures are from one
machine and one run each (best of five for speed); the scripts that produced them are not in the repository.

## Appendix 1: What a Tcl byte array is

In Tcl, a byte array is an ordinary string value whose characters are all in the range 0 to 255. Tcl stores it internally as
raw bytes; its internal type is `bytearray`. You get one from `binary format`, from reading a file with
`-translation binary`, or from `encoding convertto`. A 5-byte example (checked on Tcl 9.1):

```tcl
set ba [binary format c* {72 101 108 108 111}]
string length $ba          ;# 5
string index $ba 1         ;# e   (a character, not the number 101)
binary scan $ba cu* nums   ;# nums = 72 101 108 108 111
binary scan $ba @1cu one   ;# one = 101   (the byte at index 1)
llength $ba                ;# 1   (as a list it is just one word)
lindex $ba 1               ;# empty
```

Why it does not replace a bitarray:

- **Not a list:** it is a string. `llength` gives 1 and `lindex` gives an empty string, so `foreach` and the list commands do
  not see its bytes as elements.
- **Reading and writing a byte:** `string index` gives a character, not the number. Getting the number means `binary scan`
  with an offset, as in `@1cu`. Changing one byte means `string replace` with another `binary format`, which makes a new
  value (whether Tcl does that in place was not tested).
- **Always bytes:** there are no 16-, 32- or 64-bit elements, and nothing for 1-bit flags.
- **Quiet wrapping:** `binary format c 300` gives 44 without any error, whereas a bitarray reports the error.
- **Slow bulk route:** to get a byte array into a list you use `binary scan cu*`, which is the 42 ms against 0.5 ms
  comparison in section 4.

A byte array is the right tool for raw data you only pass along, such as network or file contents. It is not the right tool
when you want to work on the numbers inside it, which is what a bitarray is for. The two work together: `frombytes` and
`tobytes` convert between them.

## Appendix 2: Bytes, characters and numbers without the `binary` commands

The `binary` commands describe the data with a small format language (`cu*`, `@4cu`, `I`), which many people find hard to
remember. A bitarray holds the same bytes as an ordinary array of numbers, so the commands you already use for lists apply.
Each pair below was run on a small text file and gave the same answer both ways. `data` is the file read in binary mode
(`open ... rb`), and `a` is `bitarray frombytes $data`.

| task | with `binary` and `string` | with a bitarray |
|---|---|---|
| byte number 4 | `binary scan $data @4cu v` | `lindex $a 4` |
| change byte 0 to 74 | `set data [string replace $data 0 0 [binary format c 74]]` | `lset a 0 74` |
| all the bytes as a list | `binary scan $data cu* l` | already one: `foreach x $a {...}` |
| first five bytes | `binary scan [string range $data 0 4] cu* l` | `lrange $a 0 4` |
| count the newlines | `llength [regexp -all -inline \n $data]` | `bitarray count $a 0 end with 10` |
| position of the first newline | `string first [binary format c 10] $data` | `lsearch -integer $a 10` |
| reverse all the bytes | `string reverse $data` | `lreverse $a` |
| set a range to one value | `string replace $data 5 6 [string repeat . 2]` (a character; a number needs `binary format`) | `bitarray fill a 5 to 6 with 46` |
| characters as code numbers | `scan $c %c` on every character | `bitarray fromchars $text -width 16` |

The last two rows show where `string` is also simple. The bitarray is easier when the work is on numbers, and it is much
faster on large data (section 4).

**Two small helpers.** The elements are numbers, so `lset a 0 J` or `lset a $i \n` is an error (`expected integer in range
0..255`). Two one-line procs convert between a character and its number, so the code can say what it means:

```tcl
proc toord {c} {scan $c %c}       ;# character to number:  toord J  is 74,  toord \n  is 10
proc tochr {n} {format %c $n}     ;# number to character:  tochr 74  is J,   tochr 10  is a newline
```

`toord` looks at the first character only (`toord abc` is 97, with no error). Neither is built into Tcl.

Reading a file, changing it and writing it back, one command per line:

```tcl
set fh [open sample.txt rb]
set a [bitarray frombytes [read $fh]]
close $fh
lset a 0 [toord J]
foreach i [lsearch -all -integer $a [toord \n]] {lset a $i [toord " "]}
puts [tochr [lindex $a 0]]
set fh [open out.txt wb]
puts -nonewline $fh [bitarray tobytes $a]
close $fh
```

On the sample file this prints `J`, and the file `out.txt` then holds `Jello world this is a test` followed by a space: the
first byte became `J` and every newline became a space.

What a bitarray does not do: read floating-point numbers or strings out of a record, or handle byte order. To read "the 4
bytes at offset 12 as a big-endian number" you still need `binary scan` with `I`. A bitarray is a Tcl value, so you change it
with `lset a 5 3`, not `a[5] = 3`.
