#!/bin/bash
# Pipeline de decontaminación de small-RNA

# Configuración de terminación inmediata en errores
set -euo pipefail

# ==============================================================================
# CONFIGURACIÓN PRINCIPAL
# ==============================================================================
# Directorios base
DATA_DIR="data"                # Almacena archivos FASTQ crudos descargados
RES_DIR="res"                  # Contiene recursos de referencia (contaminantes)
OUT_DIR="out"                  # Resultados de procesamiento
LOG_DIR="log"                  # Archivos de registro de ejecución

# URL del archivo de contaminantes
CONTAMINANTS_URL="https://bioinformatics.cnio.es/data/courses/decont/contaminants.fasta.gz"

# IDs de las muestras a procesar
SAMPLE_IDS=("C57BL_6NJ" "SPRET_EiJ")

# ==============================================================================
# PREPARACIÓN DEL ENTORNO
# ==============================================================================
# Creación de la estructura de directorios necesaria
mkdir -p \
    "${DATA_DIR}" \                      # Descargas de datos crudos
    "${RES_DIR}/contaminants_idx" \      # Índice STAR para contaminantes
    "${OUT_DIR}"/{merged,trimmed,star} \ # Resultados intermedios y finales
    "${LOG_DIR}"/{cutadapt,star}         # Registros de ejecución detallados

# ==============================================================================
# 1. DESCARGA DE ARCHIVOS DE MUESTRAS
# ==============================================================================
echo "=== ETAPA 1: DESCARGANDO MUESTRAS ==="
while read url; do
    # Obtención del nombre de archivo desde la URL
    filename=$(basename "${url}")
    
    # Descarga solo si el archivo no existe
    if [ ! -f "${DATA_DIR}/${filename}" ]; then
        echo "Descargando: ${filename}"
        wget -q --continue -P "${DATA_DIR}" "${url}"
        
        # Validar integridad del archivo comprimido
        if ! gzip -t "${DATA_DIR}/${filename}"; then
            echo "ERROR: Archivo corrupto ${filename}" | tee -a "${LOG_DIR}/pipeline.log"
            exit 1
        fi
    fi
done < "${DATA_DIR}/urls"  # Lee URLs desde archivo en directorio data

# ==============================================================================
# 2. PROCESAMIENTO DE SECUENCIAS CONTAMINANTES
# ==============================================================================
echo "=== ETAPA 2: PROCESANDO CONTAMINANTES ==="
if [ ! -s "${RES_DIR}/contaminants.fasta" ]; then
    # Descarga de base de datos de contaminantes
    wget -q --continue -O "${RES_DIR}/contaminants.fasta.gz" "${CONTAMINANTS_URL}"
    
    # Filtrado de small nuclear RNAs (no small nucleolar)
    zcat "${RES_DIR}/contaminants.fasta.gz" | \
        seqkit grep -v -r -p "small nuclear" > "${RES_DIR}/contaminants.fasta"
    
    # Validación del archivo resultante
    if ! seqkit stat "${RES_DIR}/contaminants.fasta" >/dev/null; then
        echo "ERROR: Filtrado de contaminantes fallido" | tee -a "${LOG_DIR}/pipeline.log"
        exit 1
    fi
fi

# ==============================================================================
# 3. CREACIÓN DE ÍNDICE PARA ALINEAMIENTO
# ==============================================================================
echo "=== ETAPA 3: INDEXANDO CONTAMINANTES ==="
# Creación del índice STAR si no existe
if [ ! -f "${RES_DIR}/contaminants_idx/Genome" ]; then
    STAR --runThreadN 4 \
        --runMode genomeGenerate \
        --genomeDir "${RES_DIR}/contaminants_idx" \
        --genomeFastaFiles "${RES_DIR}/contaminants.fasta" \
        --genomeSAindexNbases 4 \        # Parámetro para genomas pequeños
        --outFileNamePrefix "${LOG_DIR}/star_index_" | tee -a "${LOG_DIR}/pipeline.log"
fi

# ==============================================================================
# 4. FUSIÓN DE RÉPLICAS TÉCNICAS
# ==============================================================================
echo "=== ETAPA 4: FUSIONANDO MUESTRAS ==="
for sample_id in "${SAMPLE_IDS[@]}"; do
    merged_file="${OUT_DIR}/merged/${sample_id}.fastq.gz"
    
    if [ ! -f "${merged_file}" ]; then
        echo "Fusionando: ${sample_id}"
        # Concatenación de todas las réplicas técnicas
        cat "${DATA_DIR}/${sample_id}"-*.fastq.gz > "${merged_file}"
        
        # Validación básica del archivo fusionado
        if [ $(zcat "${merged_file}" | head -n 4 | wc -l) -ne 4 ]; then
            echo "ERROR: Fusión fallida para ${sample_id}" | tee -a "${LOG_DIR}/pipeline.log"
            exit 1
        fi
    fi
done

# ==============================================================================
# 5. RECORTE DE ADAPTADORES
# ==============================================================================
echo "=== ETAPA 5: RECORTANDO ADAPTADORES ==="
for merged_file in "${OUT_DIR}"/merged/*.fastq.gz; do
    sample_id=$(basename "${merged_file}" .fastq.gz)
    trimmed_file="${OUT_DIR}/trimmed/${sample_id}.trimmed.fastq.gz"
    cutadapt_log="${LOG_DIR}/cutadapt/${sample_id}.log"
    
    if [ ! -f "${trimmed_file}" ]; then
        echo "Procesando: ${sample_id}"
        # Parámetros clave:
        # -m 18: Descarta reads menores a 18nt
        # -a: Secuencia del adaptador 3'
        # --discard-untrimmed: Solo conserva reads con adaptador
        cutadapt -m 18 -a TGGAATTCTCGGGTGCCAAGG \
            --discard-untrimmed \
            -o "${trimmed_file}" \
            "${merged_file}" > "${cutadapt_log}" 2>&1 || {
                echo "ERROR en cutadapt para ${sample_id}" | tee -a "${LOG_DIR}/pipeline.log"
                exit 1
            }
        
        # Extracción y registro de métricas clave
        echo "===== CUTADAPT ${sample_id} =====" >> "${LOG_DIR}/pipeline.log"
        grep -E 'Total reads processed:|Reads with adapters:' "${cutadapt_log}" >> "${LOG_DIR}/pipeline.log"
    fi
done

# ==============================================================================
# 6. ALINEAMIENTO CON STAR
# ==============================================================================
echo "=== ETAPA 6: ALINEANDO MUESTRAS ==="
for trimmed_file in "${OUT_DIR}"/trimmed/*.fastq.gz; do
    sample_id=$(basename "${trimmed_file}" .trimmed.fastq.gz)
    star_dir="${OUT_DIR}/star/${sample_id}"
    
    if [ ! -f "${star_dir}/Log.final.out" ]; then
        echo "Alineando: ${sample_id}"
        mkdir -p "${star_dir}"
        
        # Parámetros clave de STAR:
        # --outSAMtype SAM: Genera output en formato SAM
        # --outReadsUnmapped Fastx: Guarda reads no alineados en FASTQ
        # --readFilesCommand: Descompresión on-the-fly
        STAR --runThreadN 4 \
            --genomeDir "${RES_DIR}/contaminants_idx" \
            --readFilesIn "${trimmed_file}" \
            --readFilesCommand "gunzip -c" \
            --outSAMtype SAM \
            --outReadsUnmapped Fastx \
            --outFileNamePrefix "${star_dir}/" \
            --outStd Log \
            > "${LOG_DIR}/star/${sample_id}.Log.out" 2>&1 || {
                echo "ERROR en STAR para ${sample_id}" | tee -a "${LOG_DIR}/pipeline.log"
                exit 1
            }
        
        # Registro de estadísticas de alineamiento
        echo "===== STAR ${sample_id} =====" >> "${LOG_DIR}/pipeline.log"
        grep -E 'Number of input reads|Unmapped reads|% of reads mapped to multiple loci' \
            "${star_dir}/Log.final.out" >> "${LOG_DIR}/pipeline.log"
    fi
done

# ==============================================================================
# 7. REPORTE FINAL Y SALIDA
# ==============================================================================
echo "=== PIPELINE COMPLETADO ===" | tee -a "${LOG_DIR}/pipeline.log"
echo "Directorios generados:" | tee -a "${LOG_DIR}/pipeline.log"
tree -L 3 | tee -a "${LOG_DIR}/pipeline.log"  # Estructura de archivos

# Información de salida para el usuario
echo "Resultados disponibles en:"
echo " - Reads decontaminados: ${OUT_DIR}/star/*/Unmapped.out.mate1"
echo " - Log completo: ${LOG_DIR}/pipeline.log"
