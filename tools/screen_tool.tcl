# Converts the text-screen description (menus, overlays, training screens)
# into the memories and the package used by char_screen.
#
# Usage (from the repository root):
#   quartus_sh -t tools/screen_tool.tcl <screens.txt> <font.txt> <rtl dir> [preview.html]
#
# Writes <rtl dir>/MIF/pages.mif, fields.mif, words.mif and
# <rtl dir>/PKG/ui_pkg.sv (all generated; edit screens.txt instead).
#
# screens.txt (lines starting with '#' outside a page are comments):
#
#   source <NAME>                   a dynamic value, numbered in order of appearance
#   words <SET> <word>=<colour> ... a list of words selected by a value (0, 1, ...);
#                                   '_' in a word stands for a space
#   page <NAME> <scale>             scale 1: 80x60 cells of 8x8 px; scale 2: 40x30 cells of 16x16 px
#   <rows of text>                  exactly 60 (scale 1) or 30 (scale 2) rows, each at most 80 / 40
#                                   characters; ASCII 0x20..0x5F only; a line "~N" stands for
#                                   N empty rows (in text and attribute blocks)
#   attr
#   <rows of attributes>            same size; per cell: '.' or ' ' = colour 0,
#                                   '0'..'7' = colour, 'a'..'h' = colour 0..7 on a dark panel,
#                                   ':' = colour 0 on a dark panel
#   field <row> <col> <len> <fmt> <SOURCE> [<arg>]
#                                   fmt: DEC (zero-padded), DECB (leading blanks),
#                                   SDEC (sign + len-1 digits), HEX,
#                                   WORD (arg = word set), CURSOR (arg = item number:
#                                   '>' at col when the value equals the item, and the
#                                   next len-1 cells turn gold), BAR (the first
#                                   <value> cells are solid blocks, the rest '-')
#   end
#
# Colours: 0 white, 1 gold, 2 cyan, 3 dim, 4 red, 5 green, 6 grey, 7 amber.
# A cell is stored as {panel, colour[2:0], glyph[5:0]} with glyph = ASCII - 0x20.
# Page p (1..) occupies ROM words (p-1)*4800 .. p*4800-1, cell = row*80 + col.

proc fail {msg} {
    puts stderr "screen_tool: $msg"
    exit 1
}

lassign $quartus(args) src fontSrc rtlDir preview
if {$src eq "" || $fontSrc eq "" || $rtlDir eq ""} {
    fail "usage: quartus_sh -t tools/screen_tool.tcl <screens.txt> <font.txt> <rtl dir> \[preview.html\]"
}

set COLS 80
set ROWS 60
set CELLS [expr {$COLS * $ROWS}]
set MAX_FIELDS 512
set MAX_PAGES 15
set MAX_SOURCES 256
set MAX_WORDS 128
set WORD_CHARS 8
set FORMATS {DEC 0 DECB 1 SDEC 2 HEX 3 WORD 4 CURSOR 5 BAR 6}
set COLOUR_HTML {0 #dfffff 1 #ffdb00 2 #b6ffff 3 #92b6ff 4 #ff2440 5 #24ff24 6 #6d6d6d 7 #ffb600}

# ---------------------------------------------------------------- glyphs that the font really draws
set drawn [dict create]
set fh [open $fontSrc r]
foreach line [split [read $fh] "\n"] {
    if {[regexp {^glyph\s+(\S+)\s*$} $line -> name]} {
        dict set drawn [expr {$name eq "space" ? " " : $name}] 1
    }
}
close $fh

proc glyph_code {ch where} {
    global drawn
    scan $ch %c code
    if {$code < 0x20 || $code > 0x5F} { fail "$where: character '$ch' is outside ASCII 0x20..0x5F (use capitals)" }
    if {![dict exists $drawn $ch]} { fail "$where: the font has no glyph for '$ch'" }
    return [expr {$code - 0x20}]
}

proc attr_code {ch where} {
    if {$ch eq "." || $ch eq " "} { return 0 }
    if {$ch eq ":"} { return 8 }
    if {[string is digit $ch] && $ch < 8} { return $ch }
    set i [string first $ch "abcdefgh"]
    if {$i >= 0} { return [expr {8 | $i}] }
    fail "$where: bad attribute '$ch'"
}

# ---------------------------------------------------------------- parse
set fh [open $src r]
set lines [split [read $fh] "\n"]
close $fh

# Reads exactly <count> rows starting at line $i (advancing it); "~N" = N empty rows.
proc read_rows {count width what} {
    global lines i n src
    set out {}
    while {[llength $out] < $count} {
        if {$i >= $n} { fail "$what: ended after [llength $out] of $count rows" }
        set row [string trimright [lindex $lines $i] "\r"]
        incr i
        if {[regexp {^~(\d+)$} $row -> blank]} {
            for {set k 0} {$k < $blank} {incr k} { lappend out "" }
            continue
        }
        if {[string length $row] > $width} { fail "[file tail $src] line $i: row longer than $width" }
        lappend out $row
    }
    if {[llength $out] != $count} { fail "$what: [llength $out] rows, expected $count" }
    return $out
}

set sources {}
set wordSets [dict create]     ;# name -> {base count}
set words {}                   ;# list of {text colour}
set pages {}                   ;# list of page names (index = position + 1)
set pageScale [dict create]
set rom [lrepeat 0 0]
set fields {}

set i 0
set n [llength $lines]
while {$i < $n} {
    set raw [string trimright [lindex $lines $i] "\r"]
    set line [string trim $raw]
    set where "[file tail $src] line [expr {$i + 1}]"
    incr i
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    set words_ [regexp -all -inline {\S+} $line]
    switch -- [lindex $words_ 0] {
        source {
            set name [lindex $words_ 1]
            if {![regexp {^[A-Z][A-Z0-9_]*$} $name]} { fail "$where: bad source name '$name'" }
            if {[lsearch -exact $sources $name] >= 0} { fail "$where: source $name defined twice" }
            lappend sources $name
        }
        words {
            set set_ [lindex $words_ 1]
            if {[dict exists $wordSets $set_]} { fail "$where: word set $set_ defined twice" }
            set base [llength $words]
            foreach item [lrange $words_ 2 end] {
                if {![regexp {^([^=]+)=([0-7])$} $item -> text colour]} { fail "$where: expected word=colour, got '$item'" }
                set text [string map {_ " "} $text]
                if {[string length $text] > $WORD_CHARS} { fail "$where: word '$text' is longer than $WORD_CHARS" }
                foreach ch [split $text ""] { glyph_code $ch $where }
                lappend words [list $text $colour]
            }
            dict set wordSets $set_ [list $base [expr {[llength $words] - $base}]]
            if {[llength $words] > $MAX_WORDS} { fail "$where: more than $MAX_WORDS words" }
        }
        page {
            lassign [lrange $words_ 1 end] name scale
            if {![regexp {^[A-Z][A-Z0-9_]*$} $name]} { fail "$where: bad page name '$name'" }
            if {$scale ne "1" && $scale ne "2"} { fail "$where: page scale must be 1 or 2" }
            if {[lsearch -exact $pages $name] >= 0} { fail "$where: page $name defined twice" }
            lappend pages $name
            set pageIndex [llength $pages]
            if {$pageIndex > $MAX_PAGES} { fail "$where: at most $MAX_PAGES pages" }
            dict set pageScale $name $scale
            set rows [expr {$scale == 1 ? $ROWS : $ROWS / 2}]
            set cols [expr {$scale == 1 ? $COLS : $COLS / 2}]
            set cells [lrepeat $CELLS 0]
            set text [read_rows $rows $cols "page $name text"]
            set marker [string trim [lindex $lines $i]]
            incr i
            if {$marker ne "attr"} { fail "[file tail $src] line $i: expected 'attr' after $rows rows of page $name" }
            set attrs [read_rows $rows $cols "page $name attributes"]
            for {set r 0} {$r < $rows} {incr r} {
                set trow [lindex $text $r]
                set arow [lindex $attrs $r]
                for {set c 0} {$c < $cols} {incr c} {
                    set ch [string index $trow $c]
                    if {$ch eq ""} { set ch " " }
                    set ach [string index $arow $c]
                    if {$ach eq ""} { set ach "." }
                    set g [glyph_code $ch "page $name row $r col $c"]
                    set a [attr_code $ach "page $name attribute row $r col $c"]
                    lset cells [expr {$r * $COLS + $c}] [expr {($a << 6) | $g}]
                }
            }
            # fields until 'end'
            while {1} {
                if {$i >= $n} { fail "page $name: missing 'end'" }
                set fline [string trim [lindex $lines $i]]
                set fwhere "[file tail $src] line [expr {$i + 1}]"
                incr i
                if {$fline eq "" || [string index $fline 0] eq "#"} { continue }
                if {$fline eq "end"} { break }
                set f [regexp -all -inline {\S+} $fline]
                if {[lindex $f 0] ne "field"} { fail "$fwhere: expected 'field' or 'end'" }
                lassign [lrange $f 1 end] frow fcol flen ffmt fsrc farg
                foreach {v lo hi} [list $frow 0 [expr {$rows - 1}] $fcol 0 [expr {$cols - 1}] $flen 1 15] {
                    if {![string is integer -strict $v] || $v < $lo || $v > $hi} { fail "$fwhere: value '$v' outside $lo..$hi" }
                }
                if {$fcol + $flen > $cols} { fail "$fwhere: field runs past the right edge" }
                if {![dict exists $FORMATS $ffmt]} { fail "$fwhere: unknown format $ffmt" }
                set srcId [lsearch -exact $sources $fsrc]
                if {$srcId < 0} { fail "$fwhere: unknown source $fsrc" }
                set argVal 0
                if {$ffmt eq "WORD"} {
                    if {![dict exists $wordSets $farg]} { fail "$fwhere: unknown word set '$farg'" }
                    set argVal [lindex [dict get $wordSets $farg] 0]
                } elseif {$ffmt eq "CURSOR"} {
                    if {![string is integer -strict $farg]} { fail "$fwhere: CURSOR needs an item number" }
                    set argVal $farg
                } elseif {$farg ne ""} {
                    fail "$fwhere: $ffmt takes no argument"
                }
                if {$ffmt eq "DEC" || $ffmt eq "DECB" || $ffmt eq "HEX"} {
                    if {$flen > 8} { fail "$fwhere: at most 8 digits" }
                }
                if {$ffmt eq "SDEC" && ($flen < 2 || $flen > 9)} { fail "$fwhere: SDEC needs 2..9 cells" }
                set attr [expr {([lindex $cells [expr {$frow * $COLS + $fcol}]] >> 6) & 15}]
                lappend fields [list $pageIndex $frow $fcol $flen [dict get $FORMATS $ffmt] $srcId $argVal $attr]
                if {[llength $fields] > $MAX_FIELDS} { fail "$fwhere: more than $MAX_FIELDS fields" }
            }
            dict set pageText $name $text
            set rom [concat $rom $cells]
        }
        default { fail "$where: unexpected '[lindex $words_ 0]'" }
    }
}

if {[llength $pages] == 0} { fail "no pages" }
if {[llength $sources] > $MAX_SOURCES} { fail "more than $MAX_SOURCES sources" }

# ---------------------------------------------------------------- write the memories
set mifDir [file join $rtlDir MIF]
set pkgDir [file join $rtlDir PKG]
file mkdir $mifDir
file mkdir $pkgDir

proc write_mif {path width depth values comment} {
    set fh [open $path w]
    fconfigure $fh -translation lf
    puts $fh "-- Generated by tools/screen_tool.tcl; $comment"
    puts $fh "DEPTH = $depth;"
    puts $fh "WIDTH = $width;"
    puts $fh "ADDRESS_RADIX = DEC;"
    puts $fh "DATA_RADIX = HEX;"
    puts $fh "CONTENT BEGIN"
    set digits [expr {($width + 3) / 4}]
    for {set a 0} {$a < $depth} {incr a} {
        set v 0
        if {$a < [llength $values]} { set v [lindex $values $a] }
        puts $fh [format "%d : %0${digits}lX;" $a $v]
    }
    puts $fh "END;"
    close $fh
}

write_mif [file join $mifDir pages.mif] 10 [llength $rom] $rom "[llength $pages] pages x $CELLS cells, {panel, colour, glyph}"

set fieldWords {}
foreach f $fields {
    lassign $f p r c l fmt s a attr
    # {page 4, row 6, col 7, len 4, fmt 3, src 8, arg 7, attr 4} = 43 bits (MSB first)
    set v [expr {(wide($p) << 39) | (wide($r) << 33) | (wide($c) << 26) | (wide($l) << 22) |
                 (wide($fmt) << 19) | (wide($s) << 11) | (wide($a) << 4) | $attr}]
    lappend fieldWords $v
}
write_mif [file join $mifDir fields.mif] 43 $MAX_FIELDS $fieldWords "{page, row, col, len, fmt, src, arg, attr}"

set wordWords {}
foreach w $words {
    lassign $w text colour
    # {colour 3, chars 8 x 6 (first character in the top bits)} = 51 bits
    set v [expr {wide($colour)}]
    for {set k 0} {$k < $WORD_CHARS} {incr k} {
        set ch [string index $text $k]
        if {$ch eq ""} { set ch " " }
        scan $ch %c code
        set v [expr {($v << 6) | ($code - 0x20)}]
    }
    lappend wordWords $v
}
write_mif [file join $mifDir words.mif] 51 $MAX_WORDS $wordWords "{colour, 8 glyphs}"

# ---------------------------------------------------------------- package
set fh [open [file join $pkgDir ui_pkg.sv] w]
fconfigure $fh -translation lf
puts $fh "// Generated by tools/screen_tool.tcl from [file tail $src]; edit that file, not this one."
puts $fh "// Pages, dynamic value sources and memory sizes of the text screens (char_screen)."
puts $fh ""
puts $fh "package ui_pkg;"
puts $fh ""
puts $fh "  localparam int PAGE_CELLS  = $CELLS;"
puts $fh "  localparam int NUM_PAGES   = [llength $pages];"
puts $fh "  localparam int PAGE_WORDS  = [llength $rom];"
puts $fh "  localparam int MAX_FIELDS  = $MAX_FIELDS;"
puts $fh "  localparam int NUM_FIELDS  = [llength $fields];"
puts $fh "  localparam int MAX_WORDS   = $MAX_WORDS;"
puts $fh "  localparam int NUM_SOURCES = [llength $sources];"
puts $fh ""
puts $fh "  localparam logic \[3:0\] PAGE_NONE = 4'd0;"
set mask 0
set k 0
foreach p $pages {
    incr k
    puts $fh [format "  localparam logic \[3:0\] PAGE_%s = 4'd%d;   // scale %d" $p $k [dict get $pageScale $p]]
    if {[dict get $pageScale $p] == 2} { set mask [expr {$mask | (1 << $k)}] }
}
set bin ""
for {set b 15} {$b >= 0} {incr b -1} { append bin [expr {($mask >> $b) & 1}] }
puts $fh "  localparam logic \[15:0\] PAGE_SCALE2 = 16'b$bin;   // bit p = page p uses 16x16 cells"
puts $fh ""
set k 0
foreach s $sources {
    puts $fh [format "  localparam int SRC_%s = %d;" $s $k]
    incr k
}
puts $fh ""
puts $fh "  localparam logic \[2:0\] FMT_DEC    = 3'd0;"
puts $fh "  localparam logic \[2:0\] FMT_DECB   = 3'd1;"
puts $fh "  localparam logic \[2:0\] FMT_SDEC   = 3'd2;"
puts $fh "  localparam logic \[2:0\] FMT_HEX    = 3'd3;"
puts $fh "  localparam logic \[2:0\] FMT_WORD   = 3'd4;"
puts $fh "  localparam logic \[2:0\] FMT_CURSOR = 3'd5;"
puts $fh "  localparam logic \[2:0\] FMT_BAR    = 3'd6;"
puts $fh ""
puts $fh "endpackage"
close $fh

# ---------------------------------------------------------------- preview
if {$preview ne ""} {
    set fh [open $preview w]
    fconfigure $fh -translation lf
    puts $fh "<!doctype html><html><head><meta charset=\"utf-8\"><title>Text screens</title><style>"
    puts $fh "body{background:#0a1a3a;color:#dfffff;font-family:sans-serif}pre{font:14px/14px monospace;background:#003060;display:inline-block;padding:8px}"
    puts $fh ".p{background:#001040}</style></head><body>"
    set pi 0
    foreach p $pages {
        incr pi
        puts $fh "<h3>Page $p (scale [dict get $pageScale $p])</h3><pre>"
        set base [expr {($pi - 1) * $CELLS}]
        set scale [dict get $pageScale $p]
        set rows [expr {$scale == 1 ? $ROWS : $ROWS / 2}]
        set cols [expr {$scale == 1 ? $COLS : $COLS / 2}]
        for {set r 0} {$r < $rows} {incr r} {
            set out ""
            for {set c 0} {$c < $cols} {incr c} {
                set v [lindex $rom [expr {$base + $r * $COLS + $c}]]
                set ch [format %c [expr {($v & 63) + 0x20}]]
                set ch [string map {< &lt; > &gt; & &amp;} $ch]
                set colour [dict get $COLOUR_HTML [expr {($v >> 6) & 7}]]
                set cls [expr {($v >> 9) & 1 ? " class=\"p\"" : ""}]
                append out "<span$cls style=\"color:$colour\">$ch</span>"
            }
            puts $fh $out
        }
        puts $fh "</pre>"
    }
    puts $fh "</body></html>"
    close $fh
}

puts "screen_tool: [llength $pages] pages, [llength $fields] fields, [llength $words] words, [llength $sources] sources"
