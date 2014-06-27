# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Games-Go-Player.t'

#########################

use Test::More tests => 13;
BEGIN { 
  use_ok('Games::Go::Player');
  use_ok('Games::Go::Referee');
  use_ok('Games::Go::SGF');
  use_ok('File::Compare');
};

#########################

my $player = Games::Go::Player->new;         # create an object

ok( defined $player, 'Defined $player');                       # check that we got something
ok( $player->isa('Games::Go::Player'), 'Class correct');     # and it's the right class
ok( $player->teacher('5k') eq '5k', 'Teacher');

my $filename = './sgf/test.sgf';
my $referee = new Games::Go::Referee;
my $sgf = new Games::Go::SGF($filename);
my $size = 9;
ok( $player->size($size) == $size - 1 , 'Size');
ok( $player->path('./temp/') eq './temp/', 'Path');
ok( $player->increment(1) == 1, 'Increment');
ok( $player->logfile('./temp/log.txt') eq './temp/log.txt', 'Dump logfile');
ok( $player->passifopponentpasses(1) eq 1, 'pass if opponent passes');
$referee->{_coderef} = $player;
$referee->size($size);
$referee->sgffile($filename);
$player->DBdump('./temp/patternsW4');
ok( compare( './temp/log.txt', './DBlog/log.txt') == 0, 'Compare logfiles');
unlink <./temp/*>;

