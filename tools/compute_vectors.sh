#!/bin/bash

set -ex

export PYTHONPATH="${PYTHONPATH:-../plat:.}"
PLATCMD="${PLATCMD:-python ../plat/plat/bin/platcmd.py}"

MODEL_FILE="${MODEL_FILE:---model models/celeba_dlib_64_160z_d4_11/celeba_dlib_64_160z_d4_11.zip}"
MODEL_INTERFACE="${MODEL_INTERFACE:---model-interface ali.interface.AliModel}"
DATASET_VALUE="${DATASET_VALUE:-celeba_dlib_64}"
JSON_SUBDIR="${JSON_SUBDIR:-models/celeba_dlib_64_160z_d4_11}"
BATCH_SIZE="${BATCH_SIZE:-100}"
IMAGE_SIZE="${IMAGE_SIZE:-64}"

# called with offsetfile, offsetindex, outname
function sample_vector {
  $PLATCMD sample \
  --rows 1 --cols 7 --tight --gradient --offset 0 --shoulder \
  --anchor-image /develop/data/composite/$IMAGE_SIZE/pm.png \
  --image-size "$IMAGE_SIZE" \
  --numanchors 1 \
  $MODEL \
  --anchor-offset-x $2 --anchor-offset-x-minscale -1.0 --anchor-offset-x-maxscale 2.0 \
  --anchor-offset-y $2 --anchor-offset-y-minscale 0.0 --anchor-offset-y-maxscale 0.0 \
  --anchor-offset $1 \
  --outfile $JSON_SUBDIR"/atvec_"$3"_male.png"

  $PLATCMD sample \
  --rows 1 --cols 7 --tight --gradient --offset 0 --shoulder \
  --anchor-image /develop/data/composite/$IMAGE_SIZE/pf.png \
  --image-size "$IMAGE_SIZE" \
  --numanchors 1 \
  $MODEL \
  --anchor-offset-x $2 --anchor-offset-x-minscale -1.0 --anchor-offset-x-maxscale 2.0 \
  --anchor-offset-y $2 --anchor-offset-y-minscale 0.0 --anchor-offset-y-maxscale 0.0 \
  --anchor-offset $1 \
  --outfile $JSON_SUBDIR"/atvec_"$3"_female.png"
}

function atvec_thresh {
  $PLATCMD atvec \
        --thresh \
        --dataset $DATASET_VALUE \
        --split train \
        --encoded-vectors "$JSON_SUBDIR/train_vectors.json" \
        --attribute-vectors $1 \
        --outfile $2
}

function atvec_roc {
  $PLATCMD atvec \
        --roc \
        --dataset $DATASET_VALUE \
        --split valid \
        --encoded-vectors "$JSON_SUBDIR/nontrain_vectors.json" \
        --attribute-vectors $1 \
        --attribute-thresholds $4 \
        --attribute-indices $2 \
        --outfile $JSON_SUBDIR"/atvec_"$3
}

# do train vectors
if [ ! -f $JSON_SUBDIR/train_vectors.json ]; then
    $PLATCMD sample \
      $MODEL \
      --dataset=$DATASET_VALUE \
      --split train \
      --batch-size $BATCH_SIZE \
      --encoder \
      --outfile "$JSON_SUBDIR/train_vectors.json"
fi

declare -A celeba_attribs
celeba_attribs=(
  ["00"]="5_o_clock_shadow"
  ["01"]="arched_eyebrows"
  ["02"]="attractive"
  ["03"]="bags_under_eyes"
  ["04"]="bald"
  ["05"]="bangs"
  ["06"]="big_lips"
  ["07"]="big_nose"
  ["08"]="black_hair"
  ["09"]="blond_hair"
  ["10"]="blurry"
  ["11"]="brown_hair"
  ["12"]="bushy_eyebrows"
  ["13"]="chubby"
  ["14"]="double_chin"
  ["15"]="eyeglasses"
  ["16"]="goatee"
  ["17"]="gray_hair"
  ["18"]="heavy_makeup"
  ["19"]="high_cheekbones"
  ["20"]="male"
  ["21"]="mouth_slightly_open"
  ["22"]="mustache"
  ["23"]="narrow_eyes"
  ["24"]="no_beard"
  ["25"]="oval_face"
  ["26"]="pale_skin"
  ["27"]="pointy_nose"
  ["28"]="receding_hairline"
  ["29"]="rosy_cheeks"
  ["30"]="sideburns"
  ["31"]="smiling"
  ["32"]="straight_hair"
  ["33"]="wavy_hair"
  ["34"]="wearing_earrings"
  ["35"]="wearing_hat"
  ["36"]="wearing_lipstick"
  ["37"]="wearing_necklace"
  ["38"]="wearing_necktie"
  ["39"]="young"
)

if [ ! -f "$JSON_SUBDIR/nontrain_vectors.json" ]; then
    # do nontrain vectors
    $PLATCMD sample \
      $MODEL \
      --dataset=$DATASET_VALUE \
      --split nontrain \
      --batch-size $BATCH_SIZE \
      --encoder \
      --outfile "$JSON_SUBDIR/nontrain_vectors.json"
fi

# atvec all labels and a balanced male/smile/open mouth
if [ ! -f "$JSON_SUBDIR/atvecs_all.json" ]; then
    $PLATCMD atvec --dataset=$DATASET_VALUE \
      --dataset "$DATASET_VALUE" \
      --split train \
      --num-attribs 40 \
      --encoded-vectors "$JSON_SUBDIR/train_vectors.json" \
      --outfile "$JSON_SUBDIR/atvecs_all.json"

    atvec_thresh "$JSON_SUBDIR/atvecs_all.json" "$JSON_SUBDIR/atvecs_all_thresholds.json"
    for index in "${!celeba_attribs[@]}"; do
        atvec_roc     "$JSON_SUBDIR/atvecs_all.json" $index "celeba_"$index"_"${celeba_attribs[$index]} "$JSON_SUBDIR/atvecs_all_thresholds.json"
    done
    for index in "${!celeba_attribs[@]}"; do
        sample_vector "$JSON_SUBDIR/atvecs_all.json" $index "celeba_"$index"_"${celeba_attribs[$index]}
    done
fi

if [ ! -f "$JSON_SUBDIR/atvecs_balanced_20_21_31.json" ]; then
    $PLATCMD atvec --dataset=$DATASET_VALUE \
      --dataset "$DATASET_VALUE" \
      --split train \
      --num-attribs 40 \
      --encoded-vectors $JSON_SUBDIR/train_vectors.json \
      --balanced 20,21,31 \
      --outfile "$JSON_SUBDIR/atvecs_balanced_20_21_31.json"

    sample_vector "$JSON_SUBDIR/atvecs_balanced_20_21_31.json" "0" "balanced_male"
    sample_vector "$JSON_SUBDIR/atvecs_balanced_20_21_31.json" "1" "balanced_open"
    sample_vector "$JSON_SUBDIR/atvecs_balanced_20_21_31.json" "2" "balanced_smile"
fi

if [ ! -f "$JSON_SUBDIR/unblurred_train_vectors_10k.json" ]; then
    # do train blur/unblur vectors
    $PLATCMD sample \
      $MODEL \
      --anchor-glob '/develop/data/celeba/dlib_aligned_'$IMAGE_SIZE'/00????.png' \
      --batch-size $BATCH_SIZE \
      --encoder \
      --outfile "$JSON_SUBDIR/unblurred_train_vectors_10k.json"
fi

if [ ! -f "$JSON_SUBDIR/blurred1_train_vectors_10k.json" ]; then
    $PLATCMD sample \
      $MODEL \
      --anchor-glob '/develop/data/celeba/dlib_aligned_'$IMAGE_SIZE'_blur1/00????.png' \
      --batch-size $BATCH_SIZE \
      --encoder \
      --outfile "$JSON_SUBDIR/blurred1_train_vectors_10k.json"
fi

if [ ! -f "$JSON_SUBDIR/blurred2_train_vectors_10k.json" ]; then
    $PLATCMD sample \
      $MODEL \
      --anchor-glob '/develop/data/celeba/dlib_aligned_'$IMAGE_SIZE'_blur2/00????.png' \
      --batch-size $BATCH_SIZE \
      --encoder \
      --outfile "$JSON_SUBDIR/blurred2_train_vectors_10k.json"
fi

if [ ! -f "$JSON_SUBDIR/atvec_blur1.json" ]; then
    $PLATCMD atvec \
      --avg-diff "$JSON_SUBDIR/unblurred_train_vectors_10k.json,$JSON_SUBDIR/blurred1_train_vectors_10k.json" \
      --outfile "$JSON_SUBDIR/atvec_blur1.json"

    sample_vector "$JSON_SUBDIR/atvec_blur1.json" "0" "blur1"
fi

if [ ! -f "$JSON_SUBDIR/atvec_blur2.json" ]; then
    $PLATCMD atvec \
      --avg-diff "$JSON_SUBDIR/unblurred_train_vectors_10k.json,$JSON_SUBDIR/blurred2_train_vectors_10k.json" \
      --outfile "$JSON_SUBDIR/atvec_blur2.json"

    sample_vector "$JSON_SUBDIR/atvec_blur2.json" "0" "blur2"
fi

if [ ! -f "$JSON_SUBDIR/rafd_neutral_vectors.json" ]; then
    # rafd emotions
    $PLATCMD sample \
      $MODEL \
      --anchor-glob '/develop/data/rafd/aligned/'$IMAGE_SIZE'/*_neutral_*.png' \
      --batch-size $BATCH_SIZE \
      --encoder \
      --outfile "$JSON_SUBDIR/rafd_neutral_vectors.json"
fi

for EMOTION in "angry" "contemptuous" "disgusted" "fearful" "happy" "sad" "surprised"; do

    if [ ! -f "$JSON_SUBDIR/rafd_"$EMOTION"_vectors.json" ]; then
        $PLATCMD sample \
          $MODEL \
          --anchor-glob '/develop/data/rafd/aligned/'$IMAGE_SIZE'/*_'$EMOTION'_*.png' \
          --batch-size $BATCH_SIZE \
          --encoder \
          --outfile "$JSON_SUBDIR/rafd_"$EMOTION"_vectors.json"
    fi

    if [ ! -f "$JSON_SUBDIR/atvec_rafd_"$EMOTION".json" ]; then
        $PLATCMD atvec \
          --avg-diff "$JSON_SUBDIR/rafd_neutral_vectors.json","$JSON_SUBDIR/rafd_"$EMOTION"_vectors.json" \
          --outfile "$JSON_SUBDIR/atvec_rafd_"$EMOTION".json"

        sample_vector "$JSON_SUBDIR/atvec_rafd_"$EMOTION".json" "0" "rafd_"$EMOTION
    fi
done

if [ ! -f "$JSON_SUBDIR/rafd_eye_straight_vectors.json" ]; then
    # rafd emotions
    $PLATCMD sample \
      $MODEL \
      --anchor-glob '/develop/data/rafd/aligned/'$IMAGE_SIZE'/*_frontal.png' \
      --batch-size $BATCH_SIZE \
      --encoder \
      --outfile "$JSON_SUBDIR/rafd_eye_straight_vectors.json"
fi

if [ ! -f "$JSON_SUBDIR/rafd_eye_right_vectors.json" ]; then
    # rafd emotions
    $PLATCMD sample \
      $MODEL \
      --anchor-glob '/develop/data/rafd/aligned/'$IMAGE_SIZE'/*_right.png' \
      --batch-size $BATCH_SIZE \
      --encoder \
      --outfile "$JSON_SUBDIR/rafd_eye_right_vectors.json"
fi

if [ ! -f "$JSON_SUBDIR/rafd_eye_left_vectors.json" ]; then
    # rafd emotions
    $PLATCMD sample \
      $MODEL \
      --anchor-glob '/develop/data/rafd/aligned/'$IMAGE_SIZE'/*_left.png' \
      --batch-size $BATCH_SIZE \
      --encoder \
      --outfile "$JSON_SUBDIR/rafd_eye_left_vectors.json"
fi

if [ ! -f "$JSON_SUBDIR/atvec_rafd_eye_straight_to_right.json" ]; then
    $PLATCMD atvec \
      --avg-diff "$JSON_SUBDIR/rafd_eye_straight_vectors.json","$JSON_SUBDIR/rafd_eye_right_vectors.json" \
      --outfile "$JSON_SUBDIR/atvec_rafd_eye_straight_to_right.json"

    sample_vector "$JSON_SUBDIR/atvec_rafd_eye_straight_to_right.json" "0" "rafd_eye_straight_to_right"
fi

if [ ! -f "$JSON_SUBDIR/atvec_rafd_eye_straight_to_left.json" ]; then
    $PLATCMD atvec \
      --avg-diff "$JSON_SUBDIR/rafd_eye_straight_vectors.json","$JSON_SUBDIR/rafd_eye_left_vectors.json" \
      --outfile "$JSON_SUBDIR/atvec_rafd_eye_straight_to_left.json"

    sample_vector "$JSON_SUBDIR/atvec_rafd_eye_straight_to_left.json" "0" "rafd_eye_straight_to_left"
fi

if [ ! -f "$JSON_SUBDIR/atvec_rafd_eye_left_to_right.json" ]; then
    $PLATCMD atvec \
      --avg-diff "$JSON_SUBDIR/rafd_eye_left_vectors.json","$JSON_SUBDIR/rafd_eye_right_vectors.json" \
      --outfile "$JSON_SUBDIR/atvec_rafd_eye_left_to_right.json"

    sample_vector "$JSON_SUBDIR/atvec_rafd_eye_left_to_right.json" "0" "rafd_eye_left_to_right"
fi

if [ ! -f "$JSON_SUBDIR/rafd_straight_vectors.json" ]; then
    # rafd emotions
    $PLATCMD sample \
      $MODEL \
      --anchor-glob '/develop/data/rafd/aligned/'$IMAGE_SIZE'/Rafd090*.png' \
      --batch-size $BATCH_SIZE \
      --encoder \
      --outfile "$JSON_SUBDIR/rafd_straight_vectors.json"
fi

if [ ! -f "$JSON_SUBDIR/rafd_right_vectors.json" ]; then
    # rafd emotions
    $PLATCMD sample \
      $MODEL \
      --anchor-glob '/develop/data/rafd/aligned/'$IMAGE_SIZE'/Rafd045*.png' \
      --batch-size $BATCH_SIZE \
      --encoder \
      --outfile "$JSON_SUBDIR/rafd_right_vectors.json"
fi

if [ ! -f "$JSON_SUBDIR/rafd_left_vectors.json" ]; then
    # rafd emotions
    $PLATCMD sample \
      $MODEL \
      --anchor-glob '/develop/data/rafd/aligned/'$IMAGE_SIZE'/Rafd135*.png' \
      --batch-size $BATCH_SIZE \
      --encoder \
      --outfile "$JSON_SUBDIR/rafd_left_vectors.json"
fi

if [ ! -f "$JSON_SUBDIR/atvec_rafd_straight_to_right.json" ]; then
    $PLATCMD atvec \
      --avg-diff "$JSON_SUBDIR/rafd_straight_vectors.json","$JSON_SUBDIR/rafd_right_vectors.json" \
      --outfile "$JSON_SUBDIR/atvec_rafd_straight_to_right.json"

    sample_vector "$JSON_SUBDIR/atvec_rafd_straight_to_right.json" "0" "rafd_straight_to_right"
fi

if [ ! -f "$JSON_SUBDIR/atvec_rafd_straight_to_left.json" ]; then
    $PLATCMD atvec \
      --avg-diff "$JSON_SUBDIR/rafd_straight_vectors.json","$JSON_SUBDIR/rafd_left_vectors.json" \
      --outfile "$JSON_SUBDIR/atvec_rafd_straight_to_left.json"

    sample_vector "$JSON_SUBDIR/atvec_rafd_straight_to_left.json" "0" "rafd_straight_to_left"
fi

if [ ! -f "$JSON_SUBDIR/atvec_rafd_left_to_right.json" ]; then
    $PLATCMD atvec \
      --avg-diff "$JSON_SUBDIR/rafd_left_vectors.json","$JSON_SUBDIR/rafd_right_vectors.json" \
      --outfile "$JSON_SUBDIR/atvec_rafd_left_to_right.json"

    sample_vector "$JSON_SUBDIR/atvec_rafd_left_to_right.json" "0" "rafd_left_to_right"
fi
