use strict;
use warnings;
use Games::Go::Player;
use Games::Go::Referee;

my $size = shift;
my $filename = shift;
my  $increment = shift;

$increment ||= 1;

my $referee = new Games::Go::Referee;
my $player  = new Games::Go::Player;
$player->increment($increment);
$player->size($size);              # $1 is the boardsize its learning from
$player->path('/media/BIG/DBs/');  # Edit to suit your storage choice
$referee->{_coderef} = $player;    # defining coderef means Player->learn is called from Referee
$referee->size($1);
$player->teacher('5k');
$referee->sgffile($filename);
print 'Processed ', $filename, "\n";

