use strict;
use warnings;
use File::Basename;
use English;
use Games::Go::Player;
use IO::File;

my $pathname = shift;
my $pfile = shift;
my $slurpfile;

if (defined $pfile) {
  my $fh = IO::File->new($pfile, '<') or die $ERRNO;
  $slurpfile = do { local $/; <$fh> };
  $fh->close or die $ERRNO;
  $slurpfile =~ s/\n//g;
}

my $player  = new Games::Go::Player;
#$player->debug(1);
my ($filename, $dirname) = fileparse($pathname);
if ($filename =~ /(\d+)/) {
  $player->size(19);
  $player->path($dirname);
#  $player->symmetrise;
#  $player->tiestats($pathname);
  $player->updateMax;
#  $player->retrieve($pathname, $slurpfile) if defined $slurpfile;
#  $player->DBdump($pathname);
} else {
  print 'Pattern database filename must end with number'."\n";
}

