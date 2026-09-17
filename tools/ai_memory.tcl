# Reads the network memories of the board over JTAG (In-System Memory Content
# Editor): WTCH = the network WATCH AI plays (the committed champion), CHMP =
# the champion of the training run in progress.
#
# Usage (from the repository root, board programmed and connected):
#   quartus_stp -t tools/ai_memory.tcl dump                 print both memories (37 genes each)
#   quartus_stp -t tools/ai_memory.tcl save <net.txt>       WTCH in the format of tools/nn_tool.tcl
#
# A saved file can be turned into a .mif with tools/nn_tool.tcl (for example to
# study it in simulation with ai_player's NET_FILE).

proc fail {msg} {
    puts stderr "ai_memory: $msg"
    exit 1
}

set GENES 37

set hw ""
foreach h [get_hardware_names] {
    if {[string match "*DE-SoC*" $h] || $hw eq ""} { set hw $h }
}
if {$hw eq ""} { fail "no JTAG cable" }
set dev ""
foreach d [get_device_names -hardware_name $hw] {
    if {[string match "*02D020DD*" $d] || [string match "*5CS*" $d]} { set dev $d }
}
if {$dev eq ""} { fail "no Cyclone V FPGA on $hw" }

set index [dict create]
foreach info [get_editable_mem_instances -hardware_name $hw -device_name $dev] {
    # {index depth width mode type name}
    dict set index [lindex $info 5] [lindex $info 0]
}
foreach name {WTCH CHMP} {
    if {![dict exists $index $name]} { fail "memory $name not found (found: [dict keys $index])" }
}

begin_memory_edit -hardware_name $hw -device_name $dev

proc genes {name} {
    global index GENES
    set hex [read_content_from_memory -instance_index [dict get $index $name] -start_address 0 -word_count $GENES -content_in_hex]
    # the content comes back as one hex string, highest address first
    set out {}
    set n [string length $hex]
    for {set g 0} {$g < $GENES} {incr g} {
        set pos [expr {$n - 2 * ($g + 1)}]
        scan [string range $hex $pos [expr {$pos + 1}]] %x v
        lappend out [expr {$v > 127 ? $v - 256 : $v}]
    }
    return $out
}

set cmd [lindex $quartus(args) 0]
switch -- $cmd {
    dump {
        foreach name {WTCH CHMP} {
            set g [genes $name]
            puts "$name:"
            for {set j 0} {$j < 6} {incr j} {
                puts [format "  hidden %d: bias %4d  w %4d %4d %4d %4d" $j {*}[lrange $g [expr {5 * $j}] [expr {5 * $j + 4}]]]
            }
            puts [format "  output  : bias %4d  v %4d %4d %4d %4d %4d %4d" {*}[lrange $g 30 36]]
        }
    }
    save {
        set file [lindex $quartus(args) 1]
        if {$file eq ""} { fail "save <net.txt>" }
        set g [genes WTCH]
        set fh [open $file w]
        puts $fh "# WATCH AI network read from the board ([clock format [clock seconds]])"
        puts $fh "# gene value"
        for {set i 0} {$i < $GENES} {incr i} { puts $fh [format "%2d %4d" $i [lindex $g $i]] }
        close $fh
        puts "saved WTCH to $file"
    }
    default { fail "commands: dump | save <net.txt>" }
}

end_memory_edit
