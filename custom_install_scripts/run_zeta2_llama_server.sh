#!/usr/bin/env bash

./build/bin/llama-server \
  -hf bartowski/zed-industries_zeta-2-GGUF:Q4_K_M \
  --port 8000 \
  -ngl 999 \
  -c 4096 \
  -np 1 \
  --flash-attn \
  -b 4096 \
  -ub 1024
