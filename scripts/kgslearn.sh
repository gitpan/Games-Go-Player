#!/bin/bash

#Download sgf archives from the KGS website to ./tar

perl kgshoover.pl

#Untar the downloaded files to ./sgf, then delete them

for i in $(find ./tar/*.tar.gz); do
  tar --directory=./sgf --strip-components 3 -xf $i
done

rm ./tar/*.tar.gz -f

#process the sgf file, adding the information to the database files

find ./sgf -type f -exec perl learnfromfile.pl {} 1 \;

#Clean up the ./sgf directory

rm ./sgf/*.* -f

