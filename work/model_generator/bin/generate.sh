#!/bin/bash

set -e

script_dir=$(cd $(dirname $0) ; pwd)
input_dir="$script_dir/../input/entire_void_plus_T"

cd "$script_dir/../../.."

for void_file in $(ls $input_dir/void*.ttl); do
  output_dir="work/model_generator/output/entire_void_plus_T/$(basename "$void_file" .ttl)"

  echo "Processing $void_file..." >&2

  if [ ! -d "$output_dir" ]; then
    mkdir -p $output_dir
  fi

  if ! timeout 60s bundle exec rdf-config --debug --model --input void --output "$output_dir" "$void_file"; then
    echo -e "\033[31mTimeout: $void_file took longer than 60 seconds.\033[0m" >&2
  fi

  echo
done
