#!/bin/bash

# Función para verificar MD5 remoto
verify_md5() {
    local url=$1
    local file=$2
    local remote_md5=$(curl -s "${url}.md5" | cut -d' ' -f1)
    local local_md5=$(md5sum "$file" | cut -d' ' -f1)
    
    if [ "$remote_md5" != "$local_md5" ]; then
        echo "MD5 mismatch for $file"
        exit 1
    fi
}

# Verificar todas las muestras
while read url; do
    filename=$(basename "$url")
    verify_md5 "$url" "data/$filename"
done < data/urls

# Verificar contaminantes
verify_md5 "https://bioinformatics.cnio.es/data/courses/decont/contaminants.fasta.gz" \
    "res/contaminants.fasta.gz"
