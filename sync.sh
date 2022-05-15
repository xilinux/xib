#!/bin/bash

source xib_env

sync () {
    for i in $@; do
        echo "syncing from $XIB_EXPORT to $i"
        [[ $# = 0 ]] || rsync -Lta --no-perms --no-owner --no-group --delete -z -e ssh "$XIB_EXPORT/" $i
    done;
}

sync oracle2:/srv/www/xi/html/ cheetah:/srv/www/xi/html/

