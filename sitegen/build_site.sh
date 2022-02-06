#!/bin/bash
# builds the html files required for the xilinux website

generate_index () {
    envsubst < templ/index.html
}

generate_package_list() {
    local repo_dir=$1
    for info_file in $repo_dir/*.xipkg.info; do
        
    done;
}

"$XIB_CHROOT"/
