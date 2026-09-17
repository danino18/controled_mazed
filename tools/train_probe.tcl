# Reads and drives the trainer on the board over JTAG (In-System Sources and
# Probes instance TRNP, see fpga/RTL/DEBUG/train_probe.sv).
#
# Usage (from the repository root, board programmed and connected):
#   quartus_stp -t tools/train_probe.tcl status
#   quartus_stp -t tools/train_probe.tcl start <difficulty 0-2> <columns 1-3> <speed 0-7> <sim 0-7>
#   quartus_stp -t tools/train_probe.tcl stop
#   quartus_stp -t tools/train_probe.tcl exit
#   quartus_stp -t tools/train_probe.tcl release          (sources back to 0: keyboard speed again)
#   quartus_stp -t tools/train_probe.tcl log <seconds> <period> <file.csv>
#   quartus_stp -t tools/train_probe.tcl run <d> <c> <s> <sim> <seconds> <period> <file.csv>   (start + log)
#
# "start" works only while the mode menu is shown. It sets the simulation
# speed override to <sim> (7 = MAX); "release" gives the speed back to
# Numpad 4/6. "log" prints one line per new generation (and every <period>
# seconds while nothing changes) and appends it to the CSV file.

proc fail {msg} {
    puts stderr "train_probe: $msg"
    exit 1
}

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

set inst -1
foreach info [get_insystem_source_probe_instance_info -hardware_name $hw -device_name $dev] {
    if {[string match "*TRNP*" $info]} { set inst [lindex $info 0] }
}
if {$inst < 0} { fail "no In-System Sources and Probes instance TRNP (is the M11+ design programmed?)" }
start_insystem_source_probe -hardware_name $hw -device_name $dev

# ---------------------------------------------------------------- probe layout (game_system.sv)
#   [7:0] generation        [15:8] champion's generation   [41:16] champion validation score
#   [45:42] champion worlds [52:46] champion survival %     [59:53] last gen-top survival %
#   [66:60] last mean %     [72:67] stall                    [75:73] stage   [78:76] run state
#   [79] complete           [80] committed AI                [100:81] steps per second
#   [101] champion exists   [127:102] test score            [131:128] test worlds
#   [138:132] test survival [139] test valid                 [155:140] RUN ID
#   [187:156] evaluations   [189:188] result reason          [190] trainer active
proc bits {v lo hi} {
    return [expr {($v >> $lo) & ((1 << ($hi - $lo + 1)) - 1)}]
}

proc read_status {} {
    global inst
    set hex [read_probe_data -instance_index $inst -value_in_hex]
    set p [expr {"0x$hex" + 0}]          ;# Tcl integers have no size limit
    set s [dict create]
    dict set s gen        [bits $p 0 7]
    dict set s champGen   [bits $p 8 15]
    dict set s champScore [bits $p 16 41]
    dict set s champW     [bits $p 42 45]
    dict set s champSurv  [bits $p 46 52]
    dict set s topSurv    [bits $p 53 59]
    dict set s mean       [bits $p 60 66]
    dict set s stall      [bits $p 67 72]
    dict set s stage      [bits $p 73 75]
    dict set s runState   [bits $p 76 78]
    dict set s complete   [bits $p 79 79]
    dict set s committed  [bits $p 80 80]
    dict set s sps        [bits $p 81 100]
    dict set s champ      [bits $p 101 101]
    dict set s testScore  [bits $p 102 127]
    dict set s testW      [bits $p 128 131]
    dict set s testSurv   [bits $p 132 138]
    dict set s testValid  [bits $p 139 139]
    dict set s runId      [format %04X [bits $p 140 155]]
    dict set s evals      [bits $p 156 187]
    dict set s reason     [bits $p 188 189]
    dict set s active     [bits $p 190 190]
    return $s
}

proc show {s} {
    set gates [expr {[dict get $s champScore] >> 16}]
    set tgates [expr {[dict get $s testScore] >> 16}]
    return [format "gen %3d  champion: gen %3d score %8d gates %3d worlds %d/4 surv %3d%%  top %3d%%  mean %3d%%  stall %2d  sps %6d  stage %d/%d  test: %s  evals %d  run %s  active %d  committed AI %d" \
        [dict get $s gen] [dict get $s champGen] [dict get $s champScore] $gates [dict get $s champW] \
        [dict get $s champSurv] [dict get $s topSurv] [dict get $s mean] [dict get $s stall] [dict get $s sps] \
        [dict get $s stage] [dict get $s runState] \
        [expr {[dict get $s testValid] ? "score [dict get $s testScore] gates $tgates worlds [dict get $s testW]/8 surv [dict get $s testSurv]%" : "-"}] \
        [dict get $s evals] [dict get $s runId] [dict get $s active] [dict get $s committed]]
}

set source 0
proc put_source {v} {
    global inst source
    set source $v
    set bin ""
    for {set b 15} {$b >= 0} {incr b -1} { append bin [expr {($v >> $b) & 1}] }
    write_source_data -instance_index $inst -value $bin
}

set cmd [lindex $quartus(args) 0]
switch -- $cmd {
    status {
        puts [show [read_status]]
    }
    start {
        lassign [lrange $quartus(args) 1 end] diff cols speed sim
        foreach {v lo hi} [list $diff 0 2 $cols 1 3 $speed 0 7 $sim 0 7] {
            if {![string is integer -strict $v] || $v < $lo || $v > $hi} { fail "start <difficulty 0-2> <columns 1-3> <speed 0-7> <sim 0-7>" }
        }
        set cfg [expr {($diff << 3) | ($cols << 5) | ($speed << 7) | (1 << 10) | ($sim << 11)}]
        put_source $cfg
        after 200
        put_source [expr {$cfg | 1}]
        after 200
        put_source $cfg
        puts "started: difficulty $diff, $cols columns, speed $speed, simulation level $sim"
    }
    stop - exit {
        set keep 0
        set old [read_source_data -instance_index $inst -value_in_hex]
        scan $old %x keep
        set bit [expr {$cmd eq "stop" ? 2 : 4}]
        put_source [expr {$keep & ~6}]
        after 200
        put_source [expr {($keep & ~6) | $bit}]
        after 200
        put_source [expr {$keep & ~6}]
        puts "$cmd sent"
    }
    release {
        put_source 0
        puts "sources released"
    }
    log - run {
        if {$cmd eq "run"} {
            # start and log in one session, so generation 0 is not missed
            lassign [lrange $quartus(args) 1 end] diff cols speed sim seconds period csv
            set cfg [expr {($diff << 3) | ($cols << 5) | ($speed << 7) | (1 << 10) | ($sim << 11)}]
            put_source $cfg
            after 100
            put_source [expr {$cfg | 1}]
            after 100
            put_source $cfg
            puts "started: difficulty $diff, $cols columns, speed $speed, simulation level $sim"
        } else {
            lassign [lrange $quartus(args) 1 end] seconds period csv
        }
        if {$csv eq ""} { fail "log <seconds> <period> <file.csv>  |  run <d> <c> <s> <sim> <seconds> <period> <file.csv>" }
        set fh [open $csv a]
        set t0 [clock milliseconds]
        set lastGen -1
        set lastPrint 0
        while {[clock milliseconds] - $t0 < $seconds * 1000} {
            set s [read_status]
            set now [expr {([clock milliseconds] - $t0) / 1000.0}]
            if {[dict get $s gen] != $lastGen || $now - $lastPrint >= $period} {
                set lastGen [dict get $s gen]
                set lastPrint $now
                puts [format "%8.1f s  %s" $now [show $s]]
                puts $fh [join [list $now [dict get $s gen] [dict get $s champGen] [dict get $s champScore] \
                    [dict get $s champW] [dict get $s champSurv] [dict get $s topSurv] [dict get $s mean] \
                    [dict get $s stall] [dict get $s sps] [dict get $s stage] [dict get $s complete] \
                    [dict get $s testValid] [dict get $s testScore] [dict get $s testW] [dict get $s testSurv] \
                    [dict get $s evals] [dict get $s reason] [dict get $s runId]] ","]
                flush $fh
            }
            if {[dict get $s complete]} {
                # "complete" is live; the statistics come from the per-frame snapshot
                after 100
                set s [read_status]
                puts [format "%8.1f s  complete: %s" $now [show $s]]
                break
            }
            after 20
        }
        close $fh
    }
    default {
        fail "commands: status | start d c s sim | stop | exit | release | log seconds period file.csv"
    }
}

end_insystem_source_probe
