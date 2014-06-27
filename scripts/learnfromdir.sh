#!/bin/bash

dir=$1

#Process the sgf file, adding the information to the database files
#then delete the file

for file in ./$dir/*; do 
  if [ -f "$file" ]; then # was it a file
    perl learnfromfile.pl $file 1
    rm $file
  fi
done

