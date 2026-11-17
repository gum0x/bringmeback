#!/usr/bin/env bash
# BENCH_ONLY, a regular expression, limits it to the models whose names match.
# Downloads the models .github/workflows/category-bench.yaml compares, from Hugging Face, into
# $1, and prints BENCH_MODELS for test/bench/category_bench_test.dart. A model whose repository or
# file isn't found is skipped, with a note.
set -uo pipefail
dir=${1:?folder to download into}
mkdir -p "$dir"
models=""

# kind##name##repository, or search:terms##file pattern##query prefix##document prefix
while IFS= read -r spec; do
  [ -z "$spec" ] && continue
  IFS=$'\x1f' read -r kind name where pattern qp dp <<<"${spec//##/$'\x1f'}"
  if [ -n "${BENCH_ONLY:-}" ] && ! [[ $name =~ $BENCH_ONLY ]]; then continue; fi
  repos=$where
  if [[ $where == search:* ]]; then
    repos=$(curl -fsSL "https://huggingface.co/api/models?search=$(jq -rn --arg s "${where#search:}" '$s|@uri')&sort=downloads&limit=8" | jq -r '.[].id')
  fi
  found=""
  for repo in $repos; do
    file=$(curl -fsSL "https://huggingface.co/api/models/$repo" | jq -r '.siblings[].rfilename' | grep -iE "$pattern" | head -1)
    if [ -n "$file" ]; then found="$repo/$file"; break; fi
  done
  if [ -z "$found" ]; then
    echo "::warning::$name: no file matching $pattern in $where" >&2
    continue
  fi
  out="$dir/$(echo "$name" | tr -c 'A-Za-z0-9.-' '_').gguf"
  echo "$name: $found" >&2
  if curl -fsSL --retry 3 -o "$out" "https://huggingface.co/${found%%/*}/$(echo "$found" | cut -d/ -f2)/resolve/main/$(echo "$found" | cut -d/ -f3-)"; then
    models+="$kind##$name ($found)##$out##$qp##$dp;"
  else
    echo "::warning::$name: download of $found failed" >&2
  fi
done <<'SPECS'
llm##LFM2.5-350M##LiquidAI/LFM2.5-350M-GGUF##Q4_K_M\.gguf$##
llm##LFM2.5-1.2B (reference, too big)##LiquidAI/LFM2.5-1.2B-Instruct-GGUF##Q4_K_M\.gguf$##
llm##Qwen3-0.6B##search:Qwen3-0.6B GGUF##Qwen3-0\.6B.*Q4_K_M\.gguf$##
llm##Qwen2.5-0.5B-Instruct##Qwen/Qwen2.5-0.5B-Instruct-GGUF##q4_k_m\.gguf$##
llm##Gemma 3 270M##search:gemma-3-270m-it GGUF##270m.*Q8_0\.gguf$##
embed##multilingual-e5-small##search:multilingual-e5-small gguf##(f16|q8_0)\.gguf$##query: ##query: 
embed##multilingual-e5-base##search:multilingual-e5-base gguf##(q8_0)\.gguf$##query: ##query: 
embed##paraphrase-multilingual-MiniLM-L12-v2##search:paraphrase-multilingual-MiniLM-L12-v2 gguf##(f16|q8_0)\.gguf$####
embed##paraphrase-multilingual-MiniLM-L12-v2 Q8##search:paraphrase-multilingual-MiniLM-L12-v2 gguf##q8_0\.gguf$####
embed##EmbeddingGemma-300M##search:embeddinggemma-300m GGUF##Q8_0\.gguf$##task: classification | query: ##task: classification | query: 
embed##Qwen3-Embedding-0.6B##search:Qwen3-Embedding-0.6B GGUF##Q4_K_M\.gguf$##Instruct: Given a to-do list task, find the life area it belongs to\nQuery: ##
SPECS
echo "$models"
