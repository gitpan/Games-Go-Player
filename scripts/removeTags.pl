# Script to remove unwanted sgf tags from sgf files
# Adapt the $tag list as required
# Written by D.Gilder 2007

use strict;
use warnings;
use IO::File;
use English qw(-no_match_vars);

my $file = shift;
my $fh = IO::File->new($file, '<') or croak $ERRNO;
my $sgfdata = do { local $/; <$fh> };
$fh->close or croak $ERRNO;

for my $tag ('CR', 'TW', 'TB', 'LB', 'TR', 'WL', 'BL', 'OB', 'OW') {
  $sgfdata =~ s/$tag(\[.*?\])+//g
}

# The following line removes comments
$sgfdata =~ s/(?<!P|G)C\[.*?(?<!\\)\]//gs; # remove all comments
$fh = IO::File->new($file, '>') or die $ERRNO;
print $fh $sgfdata, "\n";
$fh->close or die $ERRNO;

