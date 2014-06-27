package Games::Go::Player;

use strict;
use warnings;
use DB_File;
use Carp;
our $VERSION = 0.08;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};
  $self->{_pathtoDBs} = './'; # This is altered with the path method
  $self->{_DBnameprefix} = 'patterns';
  $self->{_Maxnameprefix} = 'max';
  $self->{_size} = 18; # default board size
  $self->{_veclengths} = {};
  $self->{_maxmove} = { # maximum move number to consider when learning pattern
    1 => 500, # ie no effective maximum
    2 => 500,
    3 => 500,
    4 => 500,
    5 => 200, # a corner only pattern
    7 => 20,
    8 => 25,
   10 => 30,
   12 => 15,
   18 => 10,
  };
  $self->{_pattern}    = {}; # the current pattern
  $self->{_rating}     = {}; # the current ratings
  $self->{_psym}       = {}; # to hold symmetries of the current pattern
  $self->{_rsym}       = {}; # to hold symmetries of the current ratings
  $self->{_ratings}    = {}; # a board to find the best move
  $self->{_KGScleanup} = 0;  # KGS cleanup mode (limited passing)
  $self->{_weakest}    = '30k'; # lowest rank to learn from ( '30k' implies learn from, even if no rank information is present )
  $self->{_timeleftB}  = 100; # some initial high number so it won't pass at the beginning
  $self->{_timeleftW}  = 100;
  $self->{_psizenow}   = 0;
  $self->{_passpropensity}   = 0; # the smaller the value, the less likely it is to pass
  $self->{_ratingIncrement}  = 1; # may be set (higher) by the user, for example when learning joseki
  $self->{_incrementbygrade} = 0; # if true, increment becomes how many grades stronger than _weakest the player is.
  $self->{_debug}      = 0;
  $self->{_logfile}    = './playerlog.txt';
  bless $self, $class;
  return $self;
}

sub size {
  my $self = shift;
  my $size = shift;
  $size ||= 19;
  $size--;
  if ($size) {
    if ($size =~ /\d+/) {
      $self->{_size} = $size;
      $self->{_veclengths} = {
        1 => 1,  # for all board sizes
        2 => 3,  # for all board sizes
        3 => 4,  # for all board sizes
        4 => 7,  # for all board sizes
        5 => 9,  # for all board sizes
      };
      for ($size) {
        if    ($_ == 8)  { $self->{_veclengths}{8}  = 21; last}
        elsif ($_ == 12) { $self->{_veclengths}{7}  = 16;
                           $self->{_veclengths}{12} = 43; last
                         }
        elsif ($_ == 18) { $self->{_veclengths}{10} = 31;
                           $self->{_veclengths}{18} = 91; last
                         }
        croak 'Unsupported board size'."\n";
      }
      # how many 8 bit repetitions do i need? (1 holds 4 points)
      # For 9x9 games   use 2, 3, 4, 8
      # For 13x13 games use 2, 3, 4, 7, 12
      # For 19x19 games use 2, 3, 4, 10, 18
      # To create your own pattern size, the rule is square it, divide it by 4, round up.
      # So for example you could add 5 => 9 to create 6x6 patterns.
      # Then place an entry in for your new size in $self->{_maxmove}, eg 5 => 500
      # and edit the inrange sub
    } else {
      croak 'Illegal value ', $size;
    }
  }
  return $self->{_size}
}

sub path {
  my $self = shift;
  my $path = shift if @_;
  if ((-e $path) and (-w $path)){
    $self->{_pathtoDBs} = $path;
    for my $colour ('B', 'W') {
      my $hashfilename = $self->{_pathtoDBs}.$self->{_Maxnameprefix}.$colour;
      $self->{$hashfilename} = {};
      tie_up($hashfilename, $self->{$hashfilename});
      for (keys %{$self->{_veclengths}}) {
        $hashfilename = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$_;
        $self->{$hashfilename} = {};
        tie_up($hashfilename, $self->{$hashfilename});
      }
    }
  } else {
    croak 'Path does not exist or is not writeable: ', $path;
  }
  return $self->{_pathtoDBs}
}

sub tie_up {
  my ($filename, $hashref) = @_;
  tie %{$hashref}, "DB_File", $filename   # tie hash to database
  or die "Can't open $filename:$!\n";
}

sub teacher {
  my $self = shift;
  my $rank = shift;
  $self->{_weakest} = $rank if defined $rank and $rank =~ /^(\d{1,2})(k|d|p)\?*$/;
  return $self->{_weakest}
}

sub increment {
  my $self = shift;
  my $increment = shift;
  $self->{_ratingIncrement} = $increment if defined $increment and $increment =~ /\d+/;
  return $self->{_ratingIncrement}
}

sub incrementbygrade {
  my $self = shift;
  my $flag = shift;
  $self->{_incrementbygrade} = $flag if defined $flag and $flag=~ /0|1/;
  return $self->{_incrementbygrade}
}

sub passifopponentpasses {
  my $self = shift;
  my $flag = shift;
  $self->{_passifopponentpasses} = $flag if defined $flag and $flag=~ /0|1/;
  return $self->{_passifopponentpasses}
}

sub bypass {
  my $self = shift;
  my @psizes = @_;
  for (@psizes) {
    delete $self->{_veclengths}{$_ - 1};
  }
  return $self->{_veclengths}
} 

sub debug {
  my $self = shift;
  my $flag = shift;
  $self->{_debug} = $flag if defined $flag and $flag =~ /0|1/;
  return $self->{_debug}
}

sub passpropensity {
  my $self = shift;
  my $passpropensity = shift;
  $self->{_passpropensity} = $passpropensity if defined $passpropensity and $passpropensity =~ /[+-]?\d+/;  # matches integers
  return $self->{_passpropensity}
}

sub logfile {
  my $self = shift;
  my $logfile = shift;
  $self->{_logfile} = $logfile if defined $logfile;
  return $self->{_logfile}
}

sub _iterboard (&$) {
  my ($sub, $size) = @_;
  for my $y (0..$size){
    for my $x (0..$size){
      $sub->($x, $y);
    }
  }
}

sub initboard {
  my ($self, $referee) = @_;
}

sub update {
  my ($self, $colour, $referee, $point) = @_;
  resetratings($self);
  my @keys = sort { $b <=> $a } keys %{$self->{_veclengths}}; # biggest first

  for my $i (0..$#keys) { 
    my ($match, $thisplayable) = updateratings($self, $referee, $colour, $keys[$i]);
    myprint ($self, 'Playable area: ', $thisplayable) if $self->{_debug};
    my ($legal, $candidate) = matchedlegal($self, $colour, $referee);
    myprint ($self, 'Pattern size: ', $keys[$i], 'Match? ', $match, 'Legal? ', $legal) if $self->{_debug};
    if ($match and $legal) {
      if ($i < $#keys) {
        last #if $thisplayable > ($keys[$i+1]+1)**2; # maybe the next pattern size has an area at least as big as the one that matched
      }
    }
  }
}

# is there at least one legal, non eye-filling move in the $self->{_ratings} keys?

sub matchedlegal {
  my ($self, $colour, $referee) = @_;
  for (grep $self->{_ratings}{$_}, keys %{$self->{_ratings}}) {
    /(.*),(.*)/;
    my ($x, $y) = ($1, $2);
    my $candidate = $referee->insertpoints($x, $y);
    myprint ($self, 'Checking legality of', $x, $y, $candidate) if $self->{_debug};
    if ($referee->islegal($colour, $candidate)) {
      myprint ($self, $candidate, 'is legal') if $self->{_debug};
      return 1, $candidate unless fillingeye($self, $referee, $x, $y, $colour);
    }
  }
}

# Return an ordered list of candidate moves

sub choosemove {
  my ($self) = @_;
  my @filtered = grep $self->{_ratings}{$_}, keys %{$self->{_ratings}};
  my @keys = sort {$self->{_ratings}{$b} <=> $self->{_ratings}{$a}} @filtered;
  return @keys
}

sub chooselegalmove {
  my ($self, $colour, $referee) = @_;
  my ($point, $goodenough);
  my @suggested = choosemove($self);

  # if KGScleanup is on, don't reject a move because its rating is too low
  if ($self->{_KGScleanup}) {
    $goodenough = -50;
  } else {
    $goodenough = $self->{_passpropensity};
  }

  for (@suggested) {
    /(.*),(.*)/;
    my ($x, $y) = ($1, $2);
    my $candidate = $referee->insertpoints($x, $y);
    myprint ($self, 'Testing move:', $x, $y, $candidate) if $self->{_debug};
    if ($referee->islegal($colour, $candidate)) {
      myprint ($self, 'Is legal:', $x, $y, $candidate) if $self->{_debug};
      unless (fillingeye($self, $referee, $x, $y, $colour)) {
        if ($self->{_ratings}{$x.','.$y} > $goodenough) {
          $point = $candidate;
        }
        last;
      }
    }
  }
  return $point || pass($referee)
}

sub fillingeye {
  my ($self, $referee, $x, $y, $colour) = @_;
  my $me = ($colour eq 'B') ? 'x' : 'o';
  my $surroundings = $referee->getboardsection($x - 1, $y - 1, 2);
  my $count = 0;

  for (1,3,5,7) {
    if ((substr($surroundings, $_, 1) eq $me) or (substr($surroundings, $_, 1) eq '-')) {
      $count++;
    }
  }

  if ($count == 4) {
    $count = 0;
    $me = ($colour eq 'B') ? 'o' : 'x';
    for (0,2,6,8) {
      $count++ if substr($surroundings, $_, 1) eq $me;
      $count += 0.5 if substr($surroundings, $_, 1) eq '-';
    }
    return 1 if $count < 2
  }
  return 0
}

sub learn {
  my ($self, $colour, $point, $referee, $counter, $rank) = @_;

  if ($self->{_incrementbygrade}) {
    $self->{_ratingIncrement} = parserank($rank) - parserank($self->{_weakest}) + 1;
  }
  if (($colour eq 'B' or $colour eq 'W') and isteacher($self, $rank)) {
    unless ($referee->ispass($point)) {
      my ($x, $y) = $referee->extractpoints($point);

      for (keys %{$self->{_veclengths}}) {
        unless ($counter > $self->{_maxmove}{$_}) {
        $self->{_psizenow} = $_;
        myprint ($self, 'Pattern size is', $_) if $self->{_debug};
        myprint ($self, 'x is', $x, ', y is', $y) if $self->{_debug};

          _iterboard {
            my ($i, $j) = @_;
            my $xoffset = $x + $i - $self->{_psizenow};
            my $yoffset = $y + $j - $self->{_psizenow};
            if (inrange($self, $xoffset, $yoffset)) {
              myprint ($self, 'Inrange') if $self->{_debug};
              clearhashes($self);
              board2pattern($self, $xoffset, $yoffset, $referee);
              unless (($_ == 1 or $_ == 2 or $_ == 3 or $_ == 4) and isempty($self->{_pattern})) {
                my $hashname = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$_;
                myprint ($self, 'DB pathname is', $hashname) if $self->{_debug};
                genpattern($self, $_ - $i, $_ - $j, $colour, $hashname);
                unless ($_ == 8 or $_ == 12 or $_ == 18) { # don't reverse if whole board pattern
                  swappatterncolours($self);
                  $colour = swapcolour($self, $colour);
                  $hashname = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$_;
                  genpattern($self, $_ - $i, $_ - $j, $colour, $hashname);
                }
              }
            }
          } $_;

        }
      }

    }
  }
}

sub genpattern {
  my ($self, $i, $j, $colour, $hash) = @_;
  my $maxhash = $self->{_pathtoDBs}.$self->{_Maxnameprefix}.$colour;
  my ($max, $mcode) = findmaxvec($self);
  if (not exists $self->{$maxhash}{$$max}) {
    myprint ($self, 'Pattern not maxxed') if $self->{_debug};
    my $invcode = getinvert($mcode);
    my ($r, $s) = transformpoint($self, $invcode, $i, $j);
    my $ismaxxed = match2vec($self, $hash, $max, $r, $s);
    $self->{$maxhash}{$$max} = undef if $ismaxxed;
  }
}

sub updateratings{
  my ($self, $referee, $colour, $psize) = @_;
  my $hashname = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$psize;
  $self->{_psizenow} = $psize;
  my $match = 0;
  my $maxplayablearea = 0;
  _iterboard {
    my ($i, $j) = @_;
    my $xoffset = $i - 2;
    my $yoffset = $j - 2;
    if (inrange($self, $xoffset, $yoffset)) {
      $self->{_pattern} = {};
      $self->{_psym}    = {};
      $self->{_rsym}    = {};
      board2pattern($self, $xoffset, $yoffset, $referee);
      my ($max, $mcode) = findmaxvec($self);
      my $invcode = getinvert($mcode);
      my $vec = $self->{$hashname}{$$max};
      if ($vec) {
        $match = 1;
        # load _rating with move values
        vec2vpattern($self, $vec, $self->{_rating});
        # transform to _rsym
        transform($self, $invcode, $self->{_rsym}, $self->{_rating});
        # transform to _psym
        transform($self, $invcode, $self->{_psym}, $self->{_pattern});
        my $playablearea = playablearea($self->{_pattern});
        $maxplayablearea = $playablearea if $playablearea > $maxplayablearea;
        loadratings($self, $xoffset, $yoffset);
        if ($self->{_debug}) {
          myprint( $self, showpattern($self, $self->{_pattern}) );
          myprint ($self, ratings2string($self, $vec));
        }
      }
    }
  } $self->{_size} - $psize + 4;
  return $match, $maxplayablearea
}

# here you can define how pattern scores in the database are converted into a point's score

sub loadratings {
  my ($self, $x, $y) = @_;
#  my ($av, $sd, $max) = stats($self, $self->{_rsym}, $self->{_psym});
#  $av ||= 1;
#  my $density = density($self, $self->{_psym});
  _iterboard {
    my ($i, $j) = @_;
    my $r = $i + $x;
    my $s = $j + $y;
    unless (offboard($self, $r, $s)) {
      my $distance = dist($i, $j, $self->{_psizenow}/2, $self->{_psizenow}/2) + 0.5;
      my $ratio = bwratio($self, $self->{_psym});
      $self->{_ratings}{$r.','.$s} += ( $self->{_rsym}{$i.','.$j}*$ratio/($distance**2) );
    }
  } $self->{_psizenow};
}

# Get information about a particular pattern (for debugging)

sub retrieve {
  my ($self, $db, $str) = @_;
  clearhashes($self);
  if (defined $str) {
    my $iveclength = sqrt (length $str) - 1;
    if (exists $self->{_veclengths}{$iveclength}) {
      $self->{_psizenow} = $iveclength;
      str2temp($self, $str, $self->{_pattern});
      myprint ($self, showpattern($self, $self->{_pattern}));
      myprint ($self, 'Symmetrys ', @{findsymmetrys($self)});
      my ($vec, $tcode) = findmaxvec($self);
      vec2pattern($self, $$vec, $self->{_rsym});
      myprint ($self, 'Max of pattern ');
      myprint ($self, showpattern($self, $self->{_rsym}));
      my $ratings = $self->{$db}{$$vec};
      if ($ratings) {
        $str = ratings2string($self, $ratings);
        myprint ($self, 'Ratings');
        myprint ($self, $str);
        vec2vpattern($self, $ratings, $self->{_rating});
        myprint ($self, 'Stats ', stats($self, $self->{_rating}, $self->{_pattern}));
        myprint ($self, 'Maxxed') if mymax($self, $self->{_rating}) == 255;
      } else {
        myprint ($self, 'No ratings found');
      }
    } else {
      myprint ($self, 'Pattern of unrecognised length: ', length $str);
    }
  } else {
    myprint ($self, 'No pattern supplied'); 
  } 
}

sub DBdump {
  my ($self, $patternhash) = @_;
  clearhashes($self);
  $patternhash =~ /[a-zA-Z]*(\d+)$/;
  $self->{_psizenow} = $1;
  myprint ('Pattern size:', $self->{_psizenow}) if $self->{_debug};

  while (my ($key, $value) = each %{$self->{$patternhash}}) {
    vec2pattern($self, $key, $self->{_pattern});
    myprint ($self, showpattern($self, $self->{_pattern}));
    myprint ($self, ratings2string($self, $value));
  }

}

# get info about a pattern database (for debugging)

sub tiestats {
  my ($self, $patternhash) = @_;
  my $count;

  while (each %{$self->{$patternhash}}) {
    $count++;
  }

  myprint ($self, 'Total: ', $count) if defined $count;
}

# load the pattern hash with the board at origin x,y (size = _psize)

sub board2pattern {
  my ($self, $x, $y, $referee) = @_;
  my $pointcontents;
  $self->{_pattern} = {};
  _iterboard {
    my ($i, $j) = @_;
    my $r = $i + $x;
    my $s = $j + $y;
    if (offboard($self, $r, $s)) {
      $pointcontents = '-';
    } else {
      $pointcontents = $referee->point($r, $s);
    }
    die $x, $y, $r, $s unless defined $pointcontents;
    $self->{_pattern}{$i.','.$j} = $pointcontents;
  } $self->{_psizenow};
}


# for all patterns, symmetrise their ratings and update the hash of maxxed values

sub symmetrise {
  my $self = shift;
  
  for my $colour ('B', 'W') {
    my $maxhash = $self->{_pathtoDBs}.$self->{_Maxnameprefix}.$colour;

    for (keys %{$self->{_veclengths}}) {
      my $count = 0;
      my $patternhash = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$_;
      $self->{_psizenow} = $_;

      while (my ($key, $value) = each %{$self->{$patternhash}}) {
        $count++;
        vec2pattern($self, $key, $self->{_pattern});
        my $symref = findsymmetrys($self);
        if (@{$symref}) {
          vec2vpattern($self, $value, $self->{_rating});
          my %temp;

          _iterboard {
            my ($i, $j) = @_;
            $temp{$i.','.$j} = $self->{_rating}{$i.','.$j};
          } $self->{_psizenow};

          for (@$symref) {
            transform($self, $_, $self->{_rsym}, $self->{_rating});
            _iterboard {
              my ($i, $j) = @_;
              $temp{$i.','.$j} += $self->{_rsym}{$i.','.$j};
            } $self->{_psizenow};
          }

          my $ismaxxed = renormaliseratingpattern($self, \%temp);
          $self->{$patternhash}{$key} = vpattern2vec($self, \%temp);
          $self->{$maxhash}{$_} = undef if $ismaxxed;
        }
        print sprintf("%08d", $count), "\b\b\b\b\b\b\b\b";
      }
    }
  }

}

# Search the Dbs for maxxed ratings and update the maxxed DB accordingly

sub updateMax {
  my $self = shift;

  for my $colour ('B', 'W') {
    my $maxhash = $self->{_pathtoDBs}.$self->{_Maxnameprefix}.$colour;

    for (keys %{$self->{_veclengths}}) {
      my $patternhash = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$_;
      updateMaxthisDB($self, $maxhash, $patternhash, $_);
    }

  }
}

sub updateMaxthisDB {
  my ($self, $maxhash, $patternhash, $psize) = @_;  
  $self->{_psizenow} = $psize;

  while (my ($key, $value) = each %{$self->{$patternhash}}) {
    if (ismaxxed($self, $value)) {
      $self->{$maxhash}{$key} = undef unless exists $self->{$maxhash}{$key};
    } else {
      delete $self->{$maxhash}{$key} if exists $self->{$maxhash}{$key};
    }
  }
}

#delete keys from the MaxDB if that pattern is not maxxed

sub deletefromMaxDB {
  my $self = shift;

  for my $colour ('B', 'W') {
    my $maxhash = $self->{_pathtoDBs}.$self->{_Maxnameprefix}.$colour;
      my %test;

    while (my ($pvec, $rvec) = each %{$self->{$maxhash}}) {
      my %rhash = reverse %{$self->{_veclengths}};
      $self->{_psizenow} = $rhash{length( $pvec )};
      my $phash = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$self->{_psizenow};
      unless ( ismaxxed($self, $self->{$phash}{$pvec}) ) {
        delete $self->{$maxhash}{$pvec};
        print 'Deleted a key relating to '."$phash\n";
      }
    }

  }

}

sub statDB {

  my ($self, $patternhash) = @_;
  clearhashes($self);
  $patternhash =~ /[a-zA-Z]*(\d+)$/;
  $self->{_psizenow} = $1;
  my %stats;

  while (my ($key, $value) = each %{$self->{$patternhash}}) {
    if (defined $value) {
      vec2vpattern($self, $value, $self->{_rating});
      my $max = mymax($self, $self->{_rating});
      $stats{$max}++;
    } else {
      delete $self->{$patternhash}{$key};
    }
  }

  foreach my $key (sort {$a <=> $b} (keys(%stats))) {
    myprint( $self, $key.' '.$stats{$key});
  }

}

sub housekeepDBs {
  my $self = shift;
  $self->{_psizenow} = 4;
  for my $colour ('B', 'W') {
    my $patternhash = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.'4';

    while (my ($key, $value) = each %{$self->{$patternhash}}) {
      vec2pattern($self, $key, $self->{_pattern});
      delete $self->{$patternhash}{$key} if countofedges($self->{_pattern}) > 13;
    }
  }
}

sub countofedges {
  my $ref = shift;
  my $count = 0;
  _iterboard {
    my ($x, $y) = @_;
    $count++ if $ref->{$x.','.$y} eq '-';
  } 4;
  return $count
}

# for a pattern, find its symmetrys

sub findsymmetrys {
  my ($self) = @_;
  my @syms;
  my $holdingref = pattern2vec($self, $self->{_pattern});

  for (1..7) {
    transform($self, $_, $self->{_psym}, $self->{_pattern});
    my $vecref = pattern2vec($self, $self->{_psym});
    if ($$holdingref eq $$vecref) {
      push @syms, $_;
    }
  }

  return \@syms
}

# for a pattern, find its stringwise maximum vector

sub findmaxvec {
  my $self = shift;
  my $index = 0;
  my $holdingref = pattern2vec($self, $self->{_pattern});
  $self->{_psym} = $self->{_pattern};

  for (1..7) {
    my $hashref = {};
    transform($self, $_, $hashref, $self->{_pattern});
    my $vecref = pattern2vec($self, $hashref);
    if ($$holdingref lt $$vecref) {
      $self->{_psym} = $hashref;
      $holdingref = $vecref;
      $index = $_;
    }
  }

  return $holdingref, $index
}

sub transformpoint {
  my ($self, $matrixcode, $x, $y) = @_;
  my $offset = $self->{_psizenow};
  return $x          , $y           if $matrixcode == 0;
  return $offset - $y, $x           if $matrixcode == 1;
  return $offset - $x, $offset - $y if $matrixcode == 2;
  return $y          , $offset - $x if $matrixcode == 3;
  return $y          , $x           if $matrixcode == 4;
  return $x          , $offset - $y if $matrixcode == 5;
  return $offset - $y, $offset - $x if $matrixcode == 6;
  return $offset - $x, $y;
}

sub transform {
  my ($self, $matrixcode, $copy, $template) = @_;
  _iterboard {
    my ($i, $j) = @_;
    my ($trx, $try) = transformpoint($self, $matrixcode, $i, $j);
    $copy->{$i.','.$j} = $template->{$trx.','.$try};
  } $self->{_psizenow};
}

# update a ratings vector when a pattern match is found
# and notify of maxxed vectors

sub match2vec {
  my ($self, $hash, $vecref, $x, $y) = @_;
  my ($res, $rvec);
  my $vec = $$vecref;
  if (exists $self->{$hash}{$vec}) {
    $rvec = $self->{$hash}{$vec};
  } else {
    $rvec = chr(0) x p_area($self);
    vec($rvec, p_area($self), 8) = 0;  
  }
  my $offset = $y * ($self->{_psizenow} + 1) + $x;
  if (vec($rvec, $offset, 8) + $self->{_ratingIncrement} >= 255) {
    vec($rvec, $offset, 8) = 255;
    $res = 1;
  } else {
    vec($rvec, $offset, 8) += $self->{_ratingIncrement};
  }
  $self->{$hash}{$vec} = $rvec;
  return $res;
}

# turn a pattern hash into a string

sub showpattern{
  my ($self, $ref) = @_;
  my $h = '';
  my $size = $self->{_psizenow};
  _iterboard {
    my ($x, $y) = @_;
    $h .= $ref->{$x.','.$y};
    $h .= "\n" if $x == $size;
  } $size;
  return $h
}

# turn a ratings hash into a string

sub showratings{
  my $self = shift;
  my $h = '';
  my $size = $self->{_size};
  _iterboard {
    my ($x, $y) = @_;
    my $value = $self->{_ratings}{$x.','.$y};
    $value ||= ' . ';
    unless ($value eq ' . ') {
      $value = int $value if $value =~ /\d/;
      for ($value) {
        if (/^\d\d\d\d$/) { last }
        if (/^\d\d\d$/) { $value = $value.' '; last }
        if (/^\d\d$/)   { $value = ' '.$value.' '; last}
        if (/^\d$/)     { $value = $value.'   '; last }
      die 'Unknown rating type: '. $value."\n";
      }
    }
    $h .= '|'.$value;
    $h .= '|'."\n" if $x == $size;
  } $size;
  return $h
}

# turn a pattern hash into a pattern vector

sub pattern2vec {
  my ($self, $ref) = @_;
  my $vec = chr(0) x $self->{_veclengths}{$self->{_psizenow}};
  my $offset = 0;
  my $piece;
  _iterboard {
    my ($i, $j) = @_;
    for ($ref->{$i.','.$j}){
      if ($_ eq '.') { $piece = 0; last }
      if ($_ eq 'o') { $piece = 1; last }
      if ($_ eq 'x') { $piece = 2; last }
      if ($_ eq '-') { $piece = 3; last }
      croak 'Unknown symbol:', $_;
    }
    vec($vec, $offset, 2) = $piece;
    $offset += 1;
  } $self->{_psizenow};
  return \$vec;
}

# turn a ratings hash into a ratings vector

sub vpattern2vec {
  my ($self, $ref) = @_;
  my $offset = 0;
  my $vec = chr(0) x p_area($self);
  my $piece;
  _iterboard {
    my ($i, $j) = @_;
    vec($vec, $offset, 8) = $ref->{$i.','.$j};
    $offset += 1;
  } $self->{_psizenow};
  return $vec;
}

# turn a ratings vector into a (pattern) hash

sub vec2vpattern {
  my ($self, $vec, $ref) = @_;
  my $offset = 0;
  _iterboard {
    my ($i, $j) = @_;
    $ref->{$i.','.$j} = vec($vec, $offset, 8);
    $offset += 1;
  } $self->{_psizenow};
}

# turn a pattern vector into a pattern hash

sub vec2pattern {
  my ($self, $vec, $ref) = @_;
  my $offset = 0;
  my $piece;
  _iterboard {
    my ($i, $j) = @_;
    for (vec($vec, $offset, 2)){
      if ($_ == 0) { $piece = '.'; last }
      if ($_ == 1) { $piece = 'o'; last }
      if ($_ == 2) { $piece = 'x'; last }
      if ($_ == 3) { $piece = '-'; last }
      die 'Unknown code';
    }
    $ref->{$i.','.$j} = $piece;
    $offset += 1;
  } $self->{_psizenow};
}

# turn a ratings vector into a string for debugging

sub ratings2string {
  my ($self, $vec) = @_;
  my $offset = 0;
  my $h = '';
  my $ubound = p_area($self) - 1;
  for my $i (0..$ubound) {
    my $value = vec($vec, $offset, 8);
    for ($value) {
      if (/^\d\d\d$/) { last }
      if (/^\d\d$/)   { $value = $value.' '; last }
      if (/^\d$/)     { $value = ' '.$value.' '; last }
      die 'Unknown rating type';
    }
    $h .= '|'.$value;
    $h .= '|'."\n" if ($i + 1) % ($self->{_psizenow} + 1) == 0;
    $offset += 1;
  }
  return $h
}

# turn a string into a pattern for debugging

sub str2temp {
  my ($self, $str, $ref) = @_;
  my $piece;
  _iterboard {
    my ($i, $j) = @_;
    $ref->{$i.','.$j} = substr($str, $j * ($self->{_psizenow} + 1) + $i, 1);
  } $self->{_psizenow};
}

sub getinvert {
  my ($transnum) = @_;
  $transnum =~ tr/13/31/;
  return $transnum
}

sub resetratings {
  my ($self) = @_;
  _iterboard {
    my ($i, $j) = @_;
    $self->{_ratings}{$i.','.$j} = undef;
  } $self->{_size};
}

# You may consider using this measure when updating the ratings

sub getaverage {
  my ($self, $type) = @_;
  my $sum = 0;
  my $counter;
  _iterboard {
    my ($i, $j) = @_;
    if ($self->{$type}{$i.','.$j} =~ /\d/) {
      $sum += $self->{$type}{$i.','.$j};
      $counter++;
    }
  } $self->{_size};
  $counter ||= 1;
  return $sum/$counter
}

# change a pattern's ratings so that the highest = 255
# if the maximum value is over 255

sub renormaliseratingpattern {
  my ($self, $ref) = @_;
  my $result = 1;
  my $max = mymax($self, $ref);
  if ($max > 255) {
    my $ratio = 255/$max;
    _iterboard {
      my ($x, $y) = @_;
      $ref->{$x.','.$y} = int(($ref->{$x.','.$y} * $ratio) + 0.5);
    } $self->{_psizenow};
  } else {
    $result = 0;
  } return $result
}

sub mymax {
  my ($self, $ref) = @_;
  my $max = 0;
  _iterboard {
    my ($x, $y) = @_;
    $max = $ref->{$x.','.$y} if $ref->{$x.','.$y} > $max;
  } $self->{_psizenow};
  return $max
}

sub ismaxxed {
  my ($self, $vec) = @_;
  my $ubound = $self->{_psizenow}**2 - 1;
  for (0..$ubound){
    return 1 if vec($vec, $_, 8) == 255;
  }
  return 0
}

# You may consider using this measure when updating the ratings

sub density {
  my ($self, $ref) = @_;
  my $count = 0;
  my $empty = 0;
  _iterboard {
    my ($x, $y) = @_;
    for ($ref->{$x.','.$y}) {
      if ($_ eq 'o' or $_ eq 'x') {$count++; last}
      if ($_ eq '.') {$empty++; last}
    }
  } $self->{_psizenow};
  return ($count + 1)/($count + $empty)
}

sub bwratio {
  my ($self, $ref) = @_;
  my $bcount = 0;
  my $wcount = 0;
  _iterboard {
    my ($x, $y) = @_;
    for ($ref->{$x.','.$y}) {
      if ($_ eq 'o') {$wcount++; last}
      if ($_ eq 'x') {$bcount++; last}
    }
  } $self->{_psizenow};
  return ($wcount + $bcount + 1)/(($bcount - $wcount)**2 + 1)
}

sub offboard {
  my ($self, $x, $y) = @_;
  my $size = $self->{_size};
  return 1 if ($x < 0 or $x > $size or $y < 0 or $y > $size);
  return 0
}

# so the pattern is an edge or centre pattern, not inbetween

sub inrange {
  my ($self, $x, $y) = @_;
  my $bsize = $self->{_size};

  for ($self->{_psizenow}) {
    if ($_ == $bsize) {
      return 1 if $x == 0 and $y == 0;
      last
    }
    if ($_ == 10 and $bsize == 18) {
      return 1 if iscorner($x, $y, $bsize - $_ + 1);
      last
    }
    if ($_ == 7 and $bsize == 12) {
      return 1 if iscorner($x, $y, $bsize - $_ + 1);
      last
    }
    if ($_ == 5) {
      return 1 if iscorner($x, $y, $bsize - $_ + 1);
      last
    }
    if ($_ == 4) {
      return 1 if insquare($x, $y,  2, $bsize - 8);
      return 1 if insquare($x, $y, -2, $bsize ) and not insquare($x, $y,  0, $bsize - 4) and not toofar($x, $y, $bsize - 2);
      last
    }
    if ($_ == 3) {
      return 1 if insquare($x, $y,  2, $bsize - 7);
      return 1 if insquare($x, $y, -1, $bsize - 1) and not insquare($x, $y,  0, $bsize - 3);
      last
    }
    if ($_ == 2) {
      return 1 if insquare($x, $y, 2, $bsize - 6);
      last
    }
    if ($_ == 1) {
      return 1 if insquare($x, $y, 0, $bsize - 2);
      last
    }
    croak 'Unknown pattern size'."\n";
  }
  return 0
}

sub insquare {
  my ($x, $y, $origin, $length) = @_;
  return 0 if (($x < $origin) or
               ($x > ($origin + $length)) or
               ($y < $origin) or
               ($y > ($origin + $length)));
  return 1
}

sub iscorner {
  my ($x, $y, $q) = @_;
  return 1 if ($x == -1 and $y == -1) or
              ($x == -1 and $y == $q) or
              ($y == -1 and $x == $q) or
              ($x == $q and $y == $q);
  return 0
}

sub toofar {
  my ($x, $y, $q) = @_;
  return 1 if ($x == -2 and $y == -2) or
              ($x == -2 and $y == $q) or
              ($y == -2 and $x == $q) or
              ($x == $q and $y == $q);
  return 0
}

sub stats {
  my ($self, $rref, $pref) = @_;
  my $sum = 0;
  my $sumsquares = 0;
  my $count = 1;
  my $max = 0;
  my $current;
  _iterboard {
    my ($i, $j) = @_;
    if ($pref->{$i.','.$j} eq '.') {
      $current = $rref->{$i.','.$j};
      $sum += $current;
      $sumsquares += $current**2;
      $count++;
      $max = $current if $current > $max;
    }
  } $self->{_psizenow};
  my $av = $sum/$count;
  return $av, sqrt(($sumsquares/$count) - $av**2), $max
}

sub isteacher {
  my ($self, $rank) = @_;
  my $result = 0;
  my $rankinteger = parserank($rank);
  my $teacherrankinteger = parserank($self->{_weakest});
  
  $result = 1 if $teacherrankinteger <= $rankinteger;

  myprint ($self, 'Is teacher?', $result) if $self->{_debug};
  return $result
}

# If rank is undefined, a rank equivalent to 31k is returned

sub parserank {
  my $rank = shift;
  if (defined $rank) {
    if    ((lc $rank) =~ /^\s*(\d+)[\s-]*k/) { return -$1 + 1 }
    elsif ((lc $rank) =~ /^\s*(\d+)[\s-]*d/) { return  $1     }
    elsif ((lc $rank) =~ /^\s*(\d+)[\s-]*p/) { return  $1 + 9 }
    elsif ($rank =~ /^(\d+)/)                { return  $1/100 - 20 } # approx. conversion for elo ranks
    else                                     { return  -30    }
  }
  return -30
}

sub isempty {
  my $ref = shift;
  for (values %{$ref}) {
    return 0 if /o|x/;
  }
  return 1
}

sub playablearea {
  my $ref = shift;
  my $playable = 0;
  for (values %{$ref}) {
    $playable++ if /\.|o|x/;
  }
  return $playable
}

sub pass {
  my $referee = shift;
  if ($referee->{_const}{pointformat} eq 'sgf') {
    return ''
  } else {
    return 'pass'
  }
}

# swap black and white stones in pattern

sub swappatterncolours {
  my ($self) = @_;
  _iterboard {
    my ($x, $y) = @_;
    for ($self->{_pattern}{$x.','.$y}) {
      if ($_ eq 'x') {
        $self->{_pattern}{$x.','.$y} = 'o'
      } elsif ($_ eq 'o') {
        $self->{_pattern}{$x.','.$y} = 'x'
      }
    }
  } $self->{_psizenow}
}

sub swapcolour {
  ($_[1] eq 'B') ? 'W' : 'B'
}

sub dist {
  sqrt(($_[0] - $_[2])**2 + ($_[1] - $_[3])**2)
}

# return the area of the pattern size

sub p_area {
  my ($self) = @_;
  my $res = ($self->{_psizenow} + 1)**2;
  return $res
}

sub clearhashes {
  my ($self) = @_;
  $self->{_pattern} = {};
  $self->{_psym}    = {};
  $self->{_rating}  = {};
  $self->{_rsym}    = {};
}

sub myprint {
  my $self = shift;
  my @messages = @_;
  if (exists $messages[0]) {
	  open(LOG, ">>", $self->{_logfile}) or die 'Can\'t open'.$self->{_logfile}."\n";
		  print LOG (join ' ', @messages, "\n");
	  close(LOG);
  }
}

sub untieDBs {
  my $self = shift;
  for my $colour ('B', 'W') {
    my $hashfilename = $self->{_pathtoDBs}.$self->{_Maxnameprefix}.$colour;
    untie %{$self->{$hashfilename}};
    for (keys %{$self->{_veclengths}}) {
      $hashfilename = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$_;
      untie %{$self->{$hashfilename}};
    }
  }
}

1;

=head1 NAME

Games::Go::Player - plays a game of Go.

=head1 SYNOPSIS

This program generates a move on a Go board according to patterns 
that it learns from game records in SGF.

It puts patterns into a database (called pattern<colour><size>).
Which databases are updated depends on $self->{_veclengths}.
Pattern information is stored in a hash, where the key is the pattern,
(compressed using vec) and the value contains a score for each point
on the pattern from 0 to 255.
A pattern point is either empty, black, white, or 'not on the board'

For an example script that instructs Player to learn from a particular
directory, see pluserdir.pl in the scripts folder.

To play a move:

  my $move = $player->chooselegalmove($colour, $referee);
  $referee->play($colour, $move);
  $player->update($colour, $referee);

There are scripts in the examples folder for connecting this 'bot' to KGS or CGOS.

Before learning, the following parts of the 'new' method can (and 
in some cases, should) be edited:

$self->{_maxmove} For example, its probably not worth looking beyond move 10 when matching
whole board 19x19 games.

The function loadratings can be tweaked as you see fit. For example, at the moment it gives
a higher score to a move close to the centre of a pattern than one on the edge.

=head1 Options

=head2 path

Set to whichever pattern directory you wish to use. Default is the current directory.

  $player->path('path_to_my_pattern_directory');

=head2 teacher

When learning patterns from an sgf file, you can use this to ignore moves by players whose grade is too low.
Default is '30k'

  $player->teacher('30k'); # learn from all players, even if no grade information is present
  $player->teacher('10k'); # learn from all players of grade 10kyu and better

=head2 increment

When learning, the default is to add 1 to the frequency data associated with a pattern everytime that pattern is found.
If you want it to add more than 1, if for example you are feeding in a joseki file, use this method. 

  $player->increment(50); # learn from all players, even if no grade information is present

=head2 incrementbygrade

Similar to increment, but will increase the frequency data by however many grades the player is above teacher 

  $player->teacher('10k');
  $player->incrementbygrade(1); # a 4kyu move now increases the frequency data by 6

=head1 Debugging

The tiestats method can be called on a particular pattern file.
It counts the number of patterns in the file, and how many are 'maxxed'
ie Have a point in them that has been matched 255 times (and so are not updated again).

The retrieve method examines a pattern file for a particular pattern.
The pattern is expressed as a string of 'o', 'x', '.' and '-'
Where 'o' represents a white stone, 'x' a black one, '.' an empty point and '-' the edge of the board.
eg '-----...-...-..x' represents the top left corner pattern - 

----
-...
-...
-..x

For example: 

use File::Basename;
use Games::Go::Player;

my ($pathname, $pattern) = @_;
my $player  = new Player;
my ($filename, $dirname) = fileparse($pathname);
$filename =~ /(\d+)/;
$player->size($1);
$player->path($dirname);
$player->tiestats($filename);
$player->retrieve($pathname, $pattern) if defined $pattern;

=head1 Maintenance

The symmetrise method can be used to give a symmetrical pattern a symmetrical rating pattern.
I suggest using it on databases when a large proportion of their patterns are maxxed.

=head1 BUGS/CAVEATS

There is a memory leak (?) in learn mode that gobbles up about 1Mb/minute on a 1.86GHz machine
(which processes about 10 sgf files every 5 minutes). 
If you ask it to play on a boardsize that it has not learnt any patterns for, and it is
Black in a handicap game, it will pass as its handicap moves(!). 
KGS doesn't seem to handle this situation well, and neither does this program.

=head1 Ideas

When learning, information on the closest move (in terms of the sequence of the game) could be stored.
Have an additional piece of information in a pattern's ratings - how often this pattern has
occurred after both players pass in a scored game.
Have a maximum frequency higher than 255, then when a pattern hits that number, all updating
of patterns of that size ends.

=head1 AUTHOR (version 0.01)

DG

=cut
