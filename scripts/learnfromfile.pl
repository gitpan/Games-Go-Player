use strict;
use warnings;
use Games::Go::Player;
use Games::Go::Referee;
use Games::Go::SGF;

my $filename = shift;
my $increment = shift;

$increment ||= 1;

my $referee = new Games::Go::Referee;
my $player  = new Games::Go::Player;
my $sgf     = new Games::Go::SGF($filename, 'lc-on');
my $size = $sgf->SZ;
$player->size($size);
$player->debug(1);
$player->path('/media/BIG/DBs/');  # Edit to suit your storage choice
$player->increment($increment);
$referee->{_coderef} = $player;    # defining coderef means Player->learn is called from Referee
$referee->size($size);
$player->teacher('5k');
if ($player->isteacher($sgf->BR) or $player->isteacher($sgf->WR)) {
  $referee->sgffile($sgf, 'lc-on');
}
$player->untieDBs();
print 'Processed ', $filename, "\n";

