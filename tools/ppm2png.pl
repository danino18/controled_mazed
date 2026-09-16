#!/usr/bin/perl
# Converts a plain-text (P3) PPM, as written by sim/tb_render.sv, into a PNG.
# Usage: perl tools/ppm2png.pl in.ppm out.png [scale] [x y w h]
use strict;
use warnings;
use Compress::Zlib;

my ($in, $out, $scale, @crop) = @ARGV;
die "usage: ppm2png.pl in.ppm out.png [scale] [x y w h]\n" unless $in && $out;
$scale ||= 1;

open(my $fh, '<', $in) or die "$in: $!";
local $/;
my $text = <$fh>;
close $fh;
$text =~ s/#[^\n]*\n/\n/g;
my @tok = split ' ', $text;
die "$in: not a P3 PPM\n" unless shift(@tok) eq 'P3';
my ($w, $h, $max) = splice(@tok, 0, 3);
die "$in: truncated\n" unless @tok >= $w * $h * 3;

my ($cx, $cy, $cw, $ch) = @crop ? @crop : (0, 0, $w, $h);

my $raw = '';
for my $y ($cy .. $cy + $ch - 1) {
  my $row = '';
  for my $x ($cx .. $cx + $cw - 1) {
    my $i = ($y * $w + $x) * 3;
    $row .= pack('C3', @tok[$i .. $i + 2]) x $scale;
  }
  $raw .= ("\0" . $row) x $scale;
}

sub chunk {
  my ($type, $data) = @_;
  return pack('N', length $data) . $type . $data . pack('N', crc32($type . $data));
}

open(my $o, '>:raw', $out) or die "$out: $!";
print $o "\x89PNG\r\n\x1a\n",
  chunk('IHDR', pack('NNCCCCC', $cw * $scale, $ch * $scale, 8, 2, 0, 0, 0)),
  chunk('IDAT', compress($raw, 9)),
  chunk('IEND', '');
close $o;
