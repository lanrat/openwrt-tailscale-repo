#!/bin/bash
#set -x

if [ $# -eq 0 ]; then
    echo "No arguments provided"
    echo "pass directory to list"
    exit 1
fi

ROOT="$1"

genHTMLList() {
    i=0
    genHTMLTop
    echo "<ul>"
    # list directories
    for filepath in $(find "$ROOT" -maxdepth 1 -mindepth 1 -type d | sort); do
        path="$(basename "$filepath")"
        echo "  <li>$path</li>"
        echo "  <ul>"
        for i in $(find "$filepath" ! -iname "index.html" -maxdepth 1 -mindepth 1 -type f | sort); do
            file="$(basename "$i")"
            echo "    <li><a href=\"$path/$file\">$file</a></li>"
        done
        echo "  </ul>"
    done
    # list files
    for i in $(find "$ROOT" ! -iname "index.html" -maxdepth 1 -mindepth 1 -type f | sort); do
        file="$(basename "$i")"
        echo "    <li><a href=\"$file\">$file</a></li>"
    done
    echo "</ul>"
    genHTMLBottom
}

genHTML() {
    i=0
    genHTMLTop
    # only list files
    echo "<a href=\"../../\">Back</a>"
    echo "<table>"
    echo "<thead><tr><th>File</th><th>Size</th><th>Date</th></tr></thead>"
    echo "<tbody>"
    for i in $(find "$ROOT" ! -iname "index.html" -maxdepth 1 -mindepth 1 -type f | sort); do
        file="$(basename "$i")"
        size="$(du --apparent-size -h  "$i" | cut -f1)"
        fdate="$(date -r "$i" "+%m-%d-%Y %H:%M:%S")"
        echo "    <tr><td><a href=\"$file\">$file</a></td><td>$size</td><td>$fdate</td></tr>"
    done
    echo "</tbody>"
    echo "</table>"
    genHTMLBottom
}

genHTMLTop() {
    cat << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="https://cdn.simplecss.org/simple.min.css">
    <title>Openwrt Tailscale Repo</title>
</head>
<body>
  <header>
    <h1>Openwrt Tailscale Repo</h1>
    <p>OPKG repository for Tailscale</p>
  </header>

  <main>
EOF
}

genHTMLBottom() {
    cat << EOF
</main>

  <footer>
    <p><a href="https://github.com/lanrat/openwrt-tailscale-repo">Source on Github</a></p>
  </footer>
</body>
</html>
EOF
}


genHTML > "$ROOT/index.html"