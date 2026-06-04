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

# Curated source clips — the four ProstaTD/PSI clips that surface the six
# featured subcategories. They match the examples shown on the conference
# poster. verify_qa_overlay.py stratifies QAs per clip; if a target
# subcategory does not appear, raise --num-qas-per-clip (some subcategories
# lose the round-robin at a low cap — 40-60 reliably surfaces all of them).
CLIPS=(
    prostaTD_psiv14_clip_000293956_000295196
    prostaTD_psiv14_clip_000295992_000297244
    prostaTD_psiv14_clip_000305550_000306887
    prostaTD_psiv14_clip_000294970_000296217
    prostaTD_psiv14_clip_000323883_000325042
)

python "$PROJECT_ROOT/utils/data/verify_qa_overlay.py" \
    --video-dir    "$ROOT/video_clips" \
    --metadata-dir "$ROOT/metadata" \
    --qa-dir       "$ROOT/qa_conversations" \
    --output-dir   "$RAW" \
    --clips        "${CLIPS[@]}" \
    --num-qas-per-clip 40 \
    --no-panels \
    --no-tracks-video \
    --seed 42

# ---------------------------------------------------------------------------
# Slot table — match each gallery slot to a subcategory rendered above.
#
# verify_qa_overlay.py writes outputs as:
#   $RAW/<clip_stem>/<idx>_<Category>_<subcategory>_<difficulty>.mp4
#
# The six gallery slots (in HTML order), their source clip, and final filename:
#
#   #1  Spatial-Temporal Grounding         · identify_bbox       · psiv14_..293956 → spatiotemporal_identify_bbox.mp4
#   #2  Spatial-Temporal Interaction Cap.  · reverse_target      · psiv14_..295992 → interaction_reverse_target.mp4
#   #3  Spatial-Temporal Grounding         · trajectory          · psiv14_..305550 → spatiotemporal_trajectory.mp4
#   #4  Spatial-Temporal Interaction Cap.  · next_action_target  · psiv14_..294970 → interaction_next_action.mp4
#   #5  Spatial-Temporal Grounding         · rel_change          · psiv14_..323883 → spatiotemporal_rel_change.mp4
#   #6  Multi Choice                       · Counting:concurrent · psiv14_..293956 → multichoice_counting_concurrent.mp4
#
# These six question types are the ones featured on the SurgSTU conference
# poster (poster/figures/qa_examples/qa_pairs.txt). The Q/A text shown beneath
# each video on the page is taken verbatim from the matching qa_index.txt.
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
