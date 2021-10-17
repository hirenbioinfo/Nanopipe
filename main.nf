#!/usr/bin/env nextflow
/*
========================================================================================
                         assembly-Pipeline
========================================================================================
Nanopore Genome Analysis Pipeline.
========================================================================================
*/

def helpMessage() {
  log.info """
        Usage:

The typical command for running the pipeline is as follows:
nextflow run filema --reads /path/to/fastq --assembler <name of the assembler> --outdir /path/to/outdir/
       
Mandatory arguments:

Assembly wrokflow:
--reads                        reads fastq file
--assembler name of the assembler
--outdir name of the output dir

Optional arguments:
--threads                      Number of CPUs to use during the job
--help                         This usage statement.
-with-report                   html report file
--fast5       fast5 path
        """
}

println """\
         Nananopore Assembly - Pipeline
         ===================================
         assembler    :${params.assembler}
         reads        : ${params.reads}
         outdir       : ${params.outdir}
         """
         .stripIndent()


/*
------------------------------------------------------------------------------
                       C O N F I G U R A T I O N
------------------------------------------------------------------------------
*/

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Pipeline version
version = '1.0dev'

// Show help message
if (params.help) {
    helpMessage()
    exit 0
}
// pipeline parameter

params.fast5 = ''
params.reads = ''
params.genome_size = ''

params.output = ''
params.cpus = ''
params.mem = ''
// choose the assembler
params.assembler = ''
if (params.assembler != 'miniasm' && params.assembler != 'canu' \
    && params.assembler != 'unicycler') {
        exit 1, "--assembler: ${params.assembler}. \
        Should be 'miniasm', 'canu' or 'unicycler'"
}
// requires --genome_size for canu
if (params.assembler == 'canu' && params.genomeSize == '20000')
// requires --output
if (params.output == '') {
    exit 1, "--output is a required parameter"
}
//requires --reads
if (params.reads == '') {
    exit 1, "--reads is a required parameter"
}

raw_reads = params.rawReads
out_dir = file(params.outDir)

out_dir.mkdir()

read_pair = Channel.fromFilePairs("${raw_reads}/*R[1,2].fastq", type: 'file')

process runFastQC{
    publishDir "${out_dir}/qc/raw/${sample}", mode: 'copy', overwrite: false

    input:
        set sample, file(in_fastq) from read_pair

    output:
        file("${sample}_fastqc/*.zip") into fastqc_files

    """
    mkdir ${sample}_fastqc
    fastqc --outdir ${sample}_fastqc \
    -t ${task.cpus} \
    ${in_fastq.get(0)} \
    ${in_fastq.get(1)}
    """
}

process runMultiQC{
    tag { "${params.projectName}.rMQC" }
    publishDir "${out_dir}/qc/raw", mode: 'copy', overwrite: false

    input:
        file('*') from fastqc_files.collect()

    output:
        file('multiqc_report.html')

    """
    multiqc .
    """
}
process adapter_trimming {
    input:
  file(reads) from file(params.reads)

    output:
  file('trimmed.fastq') into trimmed_reads

script:
        """
    porechop -i "${reads}" -t "${task.cpus}" -o trimmed.fastq
        """
}

process filter_long {
    input:
  file(filtread) from file(trimmed_reads)

    output:
  file('trimmed.fastq.gz') into filtlong_reads

script:
        """
    NanoFilt -l 1000 -q 7 ${filtread} | gzip > trimmed.fastq.gz
        """
}

process assembly {
    input:
  file(filtread) from file(trimmed_reads)

    output:
  file('assembly.fasta') into filtlong_reads

script:
        """
    flye --nano-raw ${filtread} --genome-size 1m --out-dir ./flye_output
        """
}

workflow.onComplete {

    println ( workflow.success ? """
        Pipeline execution summary
        ---------------------------
        Completed at: ${workflow.complete}
        Duration    : ${workflow.duration}
        Success     : ${workflow.success}
        workDir     : ${workflow.workDir}
        exit status : ${workflow.exitStatus}
        """ : """
        Failed: ${workflow.errorReport}
        exit status : ${workflow.exitStatus}
        """
    )
}

