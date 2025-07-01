#!/bin/bash

script_dir=$(cd $(dirname $0) ; pwd)
configs_dir=$(realpath "$script_dir/../output/entire_void_plus_T")

cd "$script_dir/../../.."

for config_dir in $(ls $configs_dir); do
  echo -e "\033[32m=== ${configs_dir}/${config_dir} ===\033[0m" >&2

  if [ -n "$(ls $configs_dir/$config_dir)" ]; then
    bundle exec rdf-config --config "${configs_dir}/${config_dir}" --senbero
  else
    echo "Config directory is empty."   
  fi

  echo
done
