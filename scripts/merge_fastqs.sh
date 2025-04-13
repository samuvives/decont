#!/bin/bash

# crea la carpeta
mkdir -p out/merged

# Extraes nombres únicos de muestra de los archivos
# Para ello lista todos los archivos FASTQ comprimidos en el directorio data/, toma cada nombre de archivo y le quita la ruta data/, divide cada nombre por el guion (-) y toma la primera parte, ordena alfabéticamente y elimina duplicados y guarda esta lista en la variable samples
samples=$(ls data/*.fastq.gz | xargs -n1 basename | cut -d '-' -f1 | sort -u)

#a continuación concatena con cat las muestras creando un nuevo archivo con todas las lecturas unidas
for sample in $samples; do
    # Además comprueba si el archivo con las muestras combinadas ya existe
    if [ ! -f "out/merged/${sample}.fastq.gz" ]; then
        echo "Merging sample ${sample}"
        cat data/${sample}-*.fastq.gz > out/merged/${sample}.fastq.gz
    fi
done
