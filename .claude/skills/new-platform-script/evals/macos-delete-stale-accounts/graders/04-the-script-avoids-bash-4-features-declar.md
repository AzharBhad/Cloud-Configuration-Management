---
type: llm
focus: trace
weight: 1
---

The script avoids bash 4 features (declare -A, mapfile, readarray, ,, case conversion) and loops over arrays in an empty-safe way under set -u
