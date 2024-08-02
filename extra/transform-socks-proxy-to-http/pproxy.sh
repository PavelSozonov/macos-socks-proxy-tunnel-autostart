#!/bin/sh

/opt/homebrew/Caskroom/miniconda/base/bin/pproxy -r socks://127.0.0.1:8090 -l http://:8091
