#!/usr/bin/env bash
# Regenerate the 8 QA-overlay MP4s that ship in the project-page gallery.
#
# Run this from the repository root **after** Stage 2 has been re-executed
# (i.e. after `python utils/data/create_surgSTU_qa_dataset.py` has produced
# the per-clip conversation JSONs you want to feature).
#
# Required environment:
#   DATASET_ROOT — path containing SurgSTU/{video_clips,metadata,qa_conversations}
#
# The pinned flags below match the project-page-tuned settings:
#   --wordmark           SurgSTU branding stamp in each video
#   --text-font-scale 0.7 panel font sized for the page's ¼-width grid cells
#   --no-tracks-video    skip the bulk _tracks.mp4 (only per-QA clips needed)
#   --seed 42            byte-identical regeneration (the pipeline default)
#
# verify_qa_overlay.py emits per-clip stratified pools; you will get up to
# --num-qas-per-clip outputs per stem and then manually pick the 8 that
# match the gallery's featured subcategories.

set -euo pipefail

ROOT=${DATASET_ROOT:?set DATASET_ROOT to the SurgSTU dataset root}
PROJECT_ROOT=$(git rev-parse --show-toplevel)
OUT="$PROJECT_ROOT/SurgSTU-project/static/videos/qa_examples"
RAW="$OUT/_raw"

mkdir -p "$RAW"

# Curated source clips. Extend / replace these stems if your current dataset
# surfaces the eight featured subcategories from different files.
CLIPS=(
    cholec_01_0_21
    prostaTD_psiv15_clip_000252144_000253098
    cholec_12_2_30
    prostaTD_psiv03_clip_000180020_000181000
)

python "$PROJECT_ROOT/utils/data/verify_qa_overlay.py" \
    --video-dir    "$ROOT/video_clips" \
    --metadata-dir "$ROOT/metadata" \
    --qa-dir       "$ROOT/qa_conversations" \
    --output-dir   "$RAW" \
    --clips        "${CLIPS[@]}" \
    --num-qas-per-clip 12 \
    --wordmark \
    --text-font-scale 0.7 \
    --no-tracks-video \
    --seed 42

# ---------------------------------------------------------------------------
# Manual rename step.
#
# verify_qa_overlay.py writes each output as:
#   $RAW/<clip_stem>/<idx>_<Category>_<subcategory>_<difficulty>.mp4
#
# The gallery's <video src="..."> attributes expect:
#   $OUT/<category_lower>_<subcategory_lower>.mp4
#
# Pick one MP4 per featured subcategory and copy it up. The six targets are
# (2 rows × 3 columns in the page gallery):
#
#   spatiotemporal_locate.mp4                   (easy,   cholec, SpatioTemporal)
#   spatiotemporal_locate_by_action.mp4         (medium, prosta, SpatioTemporal)
#   multichoice_counting_concurrent.mp4         (medium, cholec, MultiChoice)
#   multichoice_existence_global.mp4            (easy,   prosta, MultiChoice)
#   interaction_next_action.mp4                 (hard,   prosta, Interaction)
#   interaction_refusal_no_specific_action.mp4  (easy,   prosta, Interaction)
#
# After picking, downsample each with ffmpeg (~640 px width, CRF 28) so each
# clip is ~1-2 MB instead of ~30 MB:
#   ffmpeg -y -i SRC.mp4 -vf "scale=640:-2" -c:v libx264 -preset medium -crf 28 \
#          -movflags +faststart -an DST.mp4
#
# Example for the first one (adjust the source path to whichever stratified
# output you want to feature):
#
#   cp "$RAW/cholec_01_0_21/0_SpatioTemporal_locate_easy.mp4" \
#      "$OUT/spatiotemporal_locate.mp4"
#
# Once all eight target files are in $OUT, you can remove the raw pool:
#   rm -rf "$RAW"
#
# Refresh the project page in a browser to verify each <video> resolves.
# ---------------------------------------------------------------------------

echo
echo "Raw stratified pool rendered to: $RAW"
echo "Pick eight MP4s and copy them to: $OUT"
echo "Expected gallery filenames are listed in the script header."
