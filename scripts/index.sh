#!/bin/bash

# Crea la carpeta de indices si no existe
mkdir -p res/contaminants_idx

# Comprueba si el index existe, y si no existe lo crea mediante STAR
if [ ! -d "res/contaminants_idx" ] || [ -z "$(ls -A res/contaminants_idx)" ]; then
    echo "Indexing contaminants..."
    STAR --runMode genomeGenerate \
        --genomeDir res/contaminants_idx \
        --genomeFastaFiles res/contaminants.fasta \
        --genomeSAindexNbases 4
else
    echo "Contaminants index already exists. Skipping."
fi
