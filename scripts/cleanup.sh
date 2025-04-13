#!/bin/bash

# Función de limpieza segura
clean_directory() {
    local dir=$1
    if [ -d "$dir" ]; then
        echo "Cleaning $dir"
        rm -rfv "$dir"/*
    fi
}

# Manejo de argumentos
if [ $# -eq 0 ]; then
    targets=("data" "res" "out" "log")
else
    targets=("$@")
fi

# Procesar cada objetivo
for target in "${targets[@]}"; do
    case $target in
        data) clean_directory "data" ;;
        resources) clean_directory "res" ;;
        output) clean_directory "out" ;;
        logs) clean_directory "log" ;;
        *) echo "Invalid target: $target" ;;
    esac
done

# Limpieza especial para índices STAR
if [[ " ${targets[@]} " =~ " resources " ]]; then
    rm -rfv res/contaminants_idx
fi
