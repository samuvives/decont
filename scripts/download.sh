#!/bin/bash

# Descargar todas las muestras en una línea
wget -i data/urls -P data --continue --quiet

# Descargar contaminantes
wget -O res/contaminants.fasta.gz "https://bioinformatics.cnio.es/data/courses/decont/contaminants.fasta.gz" --continue
