#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
echo "Compiling res_stats for $(uname -m)..."
g++ -O3 -std=c++17 res_stats.cpp -o res_stats
chmod +x res_stats
echo "Build complete: ./res_stats is ready!"
