# nf-batch-tag

This repository demonstrates an error that occurs with `nextflow` using the AWS batch executor when using carefully crafted docker container tags. The error was first discovered when workflows using short-form git commit SHA-1 IDs to tag containers failed intermittently for new commits.

The error appears to have nothing to do with AWS batch, but rather simply that strings which contain numeric characters and a single `e` are cast to floats by `nextflow` when read from the command line. For example `--value 1.1234e3` becomes `"1123.4"` when later used as a string.

With the above in mind, the example mostly serves to demonstrate a scenario when this behaviour can cause an issue.

## Setup

The files `main.nf` and `nextflow.config` define a simple workflow. that simply `cat`s an input file to an output directory.

The file `run.sh` provides a `bash` script to reproduce the error. The variables in the `Configuration` section need amending for a user's AWS environment. The script does however take the image tag as an argument to demonstrate behaviour with different values of the tag. 


## Run the example

The `run.sh` script can be demonstrated with:

    tag="good_tag"
    ./run.sh main.nf output "${tag}"

This should run fine, producing the tagged container image and running nextflow to create an output directory "output_good_tag" with a copy of the file `main.nf`. 

A failing example can be found with:

    tag="7e013608"
    ./run.sh main.nf output "${tag}"

This will lead to an error:

```
N E X T F L O W  ~  version 20.10.0
Launching `main.nf` [awesome_watson] - revision: faddf4a54c
executor >  awsbatch (1)
[69/87a91c] process > concatFile (1) [100%] 1 of 1, failed: 1 ✘
Error executing process > 'concatFile (1)'

Caused by:
  Process `concatFile (1)` terminated for an unknown reason -- Likely it has been terminated by the external system

Command executed:

  cat input.txt > output.txt

Command exit status:
  -

Command output:
  (empty)

Work dir:
  s3://<redacted>/69/87a91cf5d0fb3dbf4d5bbbbcd45e48

Tip: you can replicate the issue by changing to the process work dir and entering the command `bash .command.run`
```

Inspecting the AWS batch logs:

```
        {
            "jobArn": "arn:aws:batch:eu-west-1:<redacted>:job/fd92d089-8a4b-4af5-93c0-a93f5b66ac8e",
            "jobId": "fd92d089-8a4b-4af5-93c0-a93f5b66ac8e",
            "jobName": "concatFile_1",
            "createdAt": 1620067361882,
            "status": "FAILED",
            "statusReason": "Task failed to start",
            "stoppedAt": 1620067388711,
            "container": {
                "reason": "CannotPullContainerError: Error response from daemon: manifest for <redacted>/nf-batch-tag:Infinity not found: manifest unknown: Requested image not found"
            }
        }
```

Note here how the container image tag is listed as `Infinity`.

A similar error can be obtained with:

    tag="0e121124"
    ./run.sh main.nf output "${tag}"

which gives in the AWS batch logs:

```
"container": {
    "reason": "CannotPullContainerError: Error response from daemon: manifest for <redacted>/nf-batch-tag:0.0 not found: manifest unknown: Requested image not found"
}
```

## Explanation

It appears that the tag is at some point being intepreted as a floating point number: note the `e` in the second character and that everything else is numeric. The value `7e013608` is too large to be representable and so becomes `Infinity` whilst `0e121124` is natually `0.0`.

That this is so can be probed using additional examples:

| Command-line tag value | Tag in AWS batch log |
|------------------------|----------------------|
| 1e3                    | 1000.0               |
| 1.1e3                  | 1100.0               |
| 1.1234e3               | 1123.4               |

Using the `standard` profile of the workflow we can see that this happens in `nextflow`; the issue has nothing to do with AWS batch:

```
nextflow run main.nf -profile standard \
    -w working 
    --aws_image_tag 1.1234e3 --aws_queue <redacted> \
    --aws_image <redacted> --aws_region <redacted> \
    --output output_1.1234e3 --input run.sh

N E X T F L O W  ~  version 20.10.0
Launching `main.nf` [stupefied_volhard] - revision: faddf4a54c
executor >  local (1)
[6a/33d954] process > concatFile (1) [100%] 1 of 1, failed: 1 ✘
Error executing process > 'concatFile (1)'

Caused by:
  Process `concatFile (1)` terminated with an error exit status (125)

Command executed:

  cat input.txt > output.txt

Command exit status:
  125

Command output:
  (empty)

Command error:
  Unable to find image '<redacted>:1123.4' locally
  docker: Error response from daemon: manifest for <redacted>:1123.4 not found: manifest unknown: Requested image not found.
  See 'docker run --help'.

Work dir:
  /<redacted>/nf-batch-tag/working/6a/33d95477c40e7309e77c3a4926f42b

Tip: when you have fixed the problem you can continue the execution adding the option `-resume` to the run command line
```

Going further, we can simply `println` the tag immediately in the `main.nf`. This shows some uncontrolled type casting to be occurring.
