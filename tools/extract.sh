#1/usr/bin/env bash

if [ $# -eq 0 ]; then
    echo "No arguments provided"
    exit 1
fi

ipk="$1"

name=${ipk%.*}

echo $name
mkdir -p "$name"
tar -C "$name" -xvzf "$ipk"

mkdir -p "$name/control"
tar -C "$name/control/" -xvzf "$name/control.tar.gz"

mkdir -p "$name/data"
tar -C "$name/data/" -xvzf "$name/data.tar.gz"