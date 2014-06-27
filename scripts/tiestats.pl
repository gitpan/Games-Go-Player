use strict;
use warnings;
use File::Basename;
use English;
use Games::Go::Player;
use IO::File;

my $pathname = shift;
my $pfile;
my $size = shift;
my $slurpfile;

if (defined $pfile) {
  my $fh = IO::File->new($pfile, '<') or die $ERRNO;
  $slurpfile = do { local $/; <$fh> };
  $fh->close or die $ERRNO;
  $slurpfile =~ s/\n//g;
}

my $player  = new Games::Go::Player;
$player->logfile('./log.txt');
my ($filename, $dirname) = fileparse($pathname);
$player->size($size);
$player->path($dirname);
$player->tiestats($pathname);

