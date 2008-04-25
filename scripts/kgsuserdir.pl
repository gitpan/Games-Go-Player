use strict;
use warnings;
use Player;
use Games::Go::Referee;

my $dirname = shift;
my $filter  = shift;
my $referee = new Games::Go::Referee;
my $player  = new Games::Go::Player;
$player->size(18);
$referee->{_coderef} = $player; #defining coderef means Player-learn is called from Referee

for (sgffiles3($dirname, $filter)) {
  print $_, "\n";
  $referee->sgffile($_);
}

sub sgffiles3 {
   my ($dir) = @_;
   opendir(DB, $dir) or die "can't opendir $dir: $!";
   return sort                     # sort pathnames
          grep {    -f     }       # choose only "plain" files
          map  { "$dir/$_" }       # create full paths
          grep {  !/^\./  }        # filter out dot files
          grep { /\.sgf$/ }        # only sgf files
          readdir(DB);             # read all entries
}

sub sgffiles2 {
   my ($dir, $filter) = @_;
   opendir(DB, $dir)   or die "can't opendir $dir: $!";
   return sort                     # sort pathnames
          grep {    -f     }       # choose only "plain" files
          map  { "$dir/$_" }       # create full paths
          grep { /^$filter/ }       # filter files
          grep {  !/^\./  }        # filter out dot files
          grep { /\.sgf$/ }        # only sgf files
          readdir(DB);             # read all entries
}

sub sgffiles {
   my ($dir, $filter) = @_;
   my $char1 = substr($filter, 0, 1);
   my $char2 = substr($filter, 1, 1);
   my $char3 = substr($filter, 3, 1); #eg Aa-e
   opendir(DB, $dir)   or die "can't opendir $dir: $!";
   return sort                     # sort pathnames
          grep {    -f     }       # choose only "plain" files
          map  { "$dir/$_" }       # create full paths
          grep { /^.[$char2-$char3]/ }    # filter files
          grep { /^$char1/ }    # filter files
          grep {  !/^\./  }        # filter out dot files
          grep { /\.sgf$/ }        # only sgf files
          readdir(DB);             # read all entries
}
