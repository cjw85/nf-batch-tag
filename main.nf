
nextflow.enable.dsl = 2

process concatFile {
    cpus 1
    publishDir "${params.output}", mode: 'copy', pattern: "*"
    input:
        file "input.txt"
    output:
        file "output.txt"
    shell:
    """
    cat input.txt > output.txt
    """
}

println(params.aws_image_tag)

workflow {
    concatFile(Channel.fromPath(params.input, checkIfExists: true))
}
