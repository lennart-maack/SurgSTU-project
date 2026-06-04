#!/usr/bin/env bash
# Regenerate the 6 QA-overlay MP4s that ship in the project-page gallery.
#
# This pass produces *panel-less* renders: the surgical frame is the entire
# output, with bboxes / instance suffixes / instrument-name highlights and the
# yellow-orange (question) / cyan (answer) GT markers still drawn on every
# frame, but **without** the styled top chip+question panel or bottom answer
# panel. The Q/A text lives in HTML on the project page, below each <video>
# element — not on the video itself.
#
# Workflow (one-time per dataset regeneration):
#
#   1. Re-run Stage 2 if the dataset has changed (creates fresh QA JSONs).
#   2. Run this script — it renders a stratified pool of overlay clips per
#      featured source clip under $RAW.
#   3. Pick one MP4 per gallery slot from $RAW, downsample with the ffmpeg
#      recipe below, and copy each to qa_examples/<slot-name>.mp4 (see the
#      slot table below).
#   4. Refresh the page — the <video> tags in ../index.html already point at
#      the slot filenames; no HTML edit required.
#
# Required environment:
#   DATASET_ROOT — path containing SurgSTU/{video_clips,metadata,qa_conversations}

set -euo pipefail

ROOT=${DATASET_ROOT:?set DATASET_ROOT to the SurgSTU dataset root}
PROJECT_ROOT=$(git rev-parse --show-toplevel)
OUT="$PROJECT_ROOT/SurgSTU-project/static/videos/qa_examples"
RAW="$OUT/_raw"

mkdir -p "$RAW"

# Curated source clips. Extend / replace if your current dataset surfaces the
# six featured subcategories from different files. verify_qa_overlay.py emits
# a stratified pool per clip, so two clips × 12 QAs/clip × 3 categories
# usually yields multiple candidates for each gallery slot.
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
    --no-panels \
    --no-tracks-video \
    --seed 42

# ---------------------------------------------------------------------------
# Slot table — match each gallery slot to a subcategory rendered above.
#
# verify_qa_overlay.py writes outputs as:
#   $RAW/<clip_stem>/<idx>_<Category>_<subcategory>_<difficulty>.mp4
#
# The six gallery slots (in HTML order) and their final filenames are:
#
#   #1  Spatial-Temporal Grounding         · locate              ·  easy   · cholec → spatiotemporal_locate.mp4
#   #2  Spatial-Temporal Grounding         · locate_by_target    ·  medium · prosta → spatiotemporal_locate_by_target.mp4
#   #3  Multi Choice                       · Counting:concurrent ·  medium · cholec → multichoice_counting_concurrent.mp4
#   #4  Multi Choice                       · Existence:global    ·  easy   · prosta → multichoice_existence_global.mp4
#   #5  Spatial-Temporal Interaction Cap.  · target_interaction  ·  medium · cholec → interaction_target_interaction.mp4
#   #6  Spatial-Temporal Interaction Cap.  · comparison          ·  hard   · prosta → interaction_comparison.mp4
#
# All six picks correspond to templates that DO have explicit evaluation
# functions in evaluation/metrics.py, so the "Metric:" line on each gallery
# card is publishable today.
# ---------------------------------------------------------------------------
# Downsample recipe (target ~1-3 MB per clip):
#
#   ffmpeg -y -i $RAW/<clip>/<src>.mp4 \
#          -vf "scale=640:-2" \
#          -c:v libx264 -preset medium -crf 28 \
#          -movflags +faststart -an \
#          $OUT/<slot-name>.mp4
#
# Once all six slot files exist under $OUT, refresh the project page.
# index.html already references these filenames via <video src="..."> tags;
# no HTML edit is required.
# ---------------------------------------------------------------------------

echo
echo "Raw stratified pool rendered to: $RAW"
echo "Pick six MP4s (see slot table above), downsample with the ffmpeg recipe,"
echo "and copy each to its slot filename under: $OUT"
