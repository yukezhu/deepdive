#!/usr/bin/env bash

# Script to convert grounding files in TSV format to binary format for dimmwitted sampler
# (A direct rewrite of the python script tobinary.py)
# Usage: tobinary.sh INPUTFOLDER transform_script OUTPUTFOLDER
# It split the specific files in the input folder and for each of them calls the C++ binary to convert the format

set -eu

CHUNKSIZE=10000000
INPUTFOLDER=$1
transform_script=$2
OUTPUTFOLDER=$3

rm -rf "$INPUTFOLDER"/dd_tmp
mkdir -p "$INPUTFOLDER"/dd_tmp
rm -rf "$INPUTFOLDER"/nedges_

# handle factors
while IFS=$'\t' read factor_name function_id positives; do
    _args= nvars=0
    for p in $positives; do
        case $p in
            true) _args+=1 ;;
            false) _args+=0 ;;
        esac
        let ++nvars
    done

    echo "SPLITTING ${factor_name}..."
    split -a 10 -l $CHUNKSIZE "$INPUTFOLDER"/dd_factors_${factor_name}_out "$INPUTFOLDER"/dd_tmp/dd_factors_${factor_name}_out

    echo "BINARIZE ${factor_name}..."
    ls "$INPUTFOLDER"/dd_tmp |
    egrep "^dd_factors_${factor_name}_out" |
    xargs -P 40 -I {} -n 1 \
      "$transform_script" factor "$INPUTFOLDER"/dd_tmp/{} ${function_id} ${nvars} ${_args} |
    awk '{s+=$1} END {printf "%.0f\n", s}' >>"$INPUTFOLDER"/dd_nedges_
done <"$INPUTFOLDER"/dd_factormeta


# handle variables
for f in "$INPUTFOLDER"/dd_variables_*; do
    echo "SPLITTING ${f}..."
    split -a 10 -l $CHUNKSIZE "$INPUTFOLDER"/"${f}" "$INPUTFOLDER"/dd_tmp/"${f}"

    echo "BINARIZE ${f}..."
    ls "$INPUTFOLDER"/dd_tmp | egrep "^${f}" |
    xargs -P 40 -I {} -n 1 \
      "$transform_script" variable "$INPUTFOLDER"/dd_tmp/{}
done

# handle weights
echo "BINARIZE weights..."
"$transform_script" weight "$INPUTFOLDER"/dd_weights

# move files
rm -rf "$INPUTFOLDER"/dd_factors
mkdir -p "$INPUTFOLDER"/dd_factors
mv "$INPUTFOLDER"/dd_tmp/dd_factors*.bin "$INPUTFOLDER"/dd_factors

rm -rf "$INPUTFOLDER"/dd_variables
mkdir -p "$INPUTFOLDER"/dd_variables
mv "$INPUTFOLDER"/dd_tmp/dd_variables*.bin "$INPUTFOLDER"/dd_variables

# counting
nfactor_files=0
nvariable_files=0
echo "COUNTING variables..."
echo $(
        wc -l "$INPUTFOLDER"/dd_tmp/dd_variables_* | tail -n 1 |
        sed -e 's/^[ \t]*//g' |
        cut -d ' ' -f 1
    ) + ${nvariable_files} | bc >"$INPUTFOLDER"/dd_nvariables

echo "COUNTING factors..."
echo $(
        wc -l "$INPUTFOLDER"/dd_tmp/dd_factors_* | tail -n 1 |
        sed -e 's/^[ \t]*//g' |
        cut -d ' ' -f 1
    ) + ${nvariable_files} | bc >"$INPUTFOLDER"/dd_nfactors

echo "COUNTING weights..."
wc -l "$INPUTFOLDER"/dd_tmp/dd_weights | tail -n 1 |
sed -e 's/^[ \t]*//g' |
cut -d ' ' -f 1 >"$INPUTFOLDER"/dd_nweights

# XXX echo "COUNTING edges..."
awk '{{ sum += $1 }} END {{ printf "%.0f\n", sum }}' "$INPUTFOLDER"/dd_nedges_ >"$INPUTFOLDER"/dd_nedges

# concatenate files
echo "CONCATENATING FILES..."
cat "$INPUTFOLDER"/dd_nweights "$INPUTFOLDER"/dd_nvariables "$INPUTFOLDER"/dd_nfactors "$INPUTFOLDER"/dd_nedges |
tr '\n' ',' >"$INPUTFOLDER"/graph.meta
# XXX what the heck? why are we outputting outputfolder paths to input folder?
echo "$OUTPUTFOLDER"/graph.weights,"$OUTPUTFOLDER"/graph.variables,"$OUTPUTFOLDER"/graph.factors,"$OUTPUTFOLDER"/graph.edges >>"$INPUTFOLDER"/graph.meta
if [[ "$INPUTFOLDER" != "$OUTPUTFOLDER" ]]; then
    mv  "$INPUTFOLDER"/graph.meta                         "$OUTPUTFOLDER"/graph.meta
    mv  "$INPUTFOLDER"/dd_weights.bin                     "$OUTPUTFOLDER"/dd_weights
    cat "$INPUTFOLDER"/dd_variables/*                    >"$OUTPUTFOLDER"/graph.variables
    cat "$INPUTFOLDER"/dd_factors/dd_factors*factors.bin >"$OUTPUTFOLDER"/graph.factors
    cat "$INPUTFOLDER"/dd_factors/dd_factors*edges.bin   >"$OUTPUTFOLDER"/graph.edges
fi

# clean up folder
echo "Cleaning up files"
rm -rf "$INPUTFOLDER"/dd_*
