# Milestone Log

Measurements are from Quartus Prime Lite 17.0.0 Build 595, full compile (`quartus_sh --flow compile`), device 5CSXFC6D6F31C6 (41,910 ALMs, 5,662,720 memory bits, 553 M10K, 112 DSP).

| Milestone | Compile time | ALMs | Registers | Memory bits | M10K | DSP | Setup slack @31.5 MHz | Board check |
|---|---|---|---|---|---|---|---|---|
| M0 supplied `VGA_DEMO_Students` (unmodified) | 86 s | 787 (2%) | 592 | 2,555,904 (45%) | 312 (56%) | 0 | +17.39 ns (Fmax 69.7 MHz) | pending |

## M0 — Baseline of the supplied demo

Restore the reference copy (it is ignored by Git and can be regenerated):

```
cd reference
quartus_sh --restore -output vga_demo ../qar_files_from_labs/VGA_DEMO_Students.qar
cd vga_demo
quartus_sh --flow compile Lab1Demo
```

Findings:
- It compiles with 0 errors. The path contains a space (`controled mazed`), and neither restore nor compile had a problem with it.
- Memory use is dominated by `vga_bg.mif` (307,200 × 8 bits). This confirms the design decision to avoid a full-screen background ROM.
- The supplied `DE10_Standard_Audio.sdc` is a Terasic template. Two `create_generated_clock` lines are ignored (critical warnings) because their hierarchy paths do not exist, and it also references ports that the design does not have (`DRAM_*`, `VGA_CLK`, `AUD_BCLK`). The 31.5 MHz clock is still constrained through `derive_pll_clocks`. Our project will use a minimal, clean SDC instead.
- Nine debug outputs of the demo have no pin assignment (critical warning 169085). This is harmless in the demo.
- The keyboard block (`KBDINTF.qxp`) and the audio codec (`audio_codec_controller.QXP`) are precompiled netlists. Their ports, recovered from the demo schematics, are:
  - `KBDINTF(CLOCK_50, resetN, PS2_CLK, PS2_DAT → keyCode[8:0], make, break)`. `break` is a SystemVerilog keyword, so this block must be instantiated from a Verilog-2001 wrapper or with an escaped identifier.
  - `audio_codec_controller(CLOCK31_5, resetN, AUD_ADCLRCK, AUD_BCLK, dacdata_left[15:0], dacdata_right[15:0] → AUD_DACDAT, AUD_XCK, AUD_I2C_SCLK, adcdata_left/right; inout AUD_I2C_SDAT)`.
  - `CLK_31P5(refclk, rst → outclk_0, locked)`.
