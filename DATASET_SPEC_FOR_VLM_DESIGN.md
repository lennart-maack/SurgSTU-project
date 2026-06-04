# SurgSTU Dataset Specification for VLM Architecture Design

This document describes the SurgSTU benchmark in enough detail for a VLM
architecture designer to reason about what capabilities the model needs,
where current architectures fall short, and what structural inductive biases
would help. It is **not** a dataset card — it is an engineering spec.

---

## 1. Executive summary

| Property | Value |
|---|---|
| QA conversations | **32 802** (11 549 cholec + 21 253 prosta) |
| Video clips | **1 622** (694 cholec + 928 prosta) |
| Source procedures | **16** (8 cholecystectomy + 8 prostatectomy) |
| QA templates | **30** across 3 categories |
| Clip FPS | 15 fps |
| Clip resolution | 854 × 480 (cholec) / 1920 × 1080 (prosta) |
| Clip duration | ~20–30 s each |
| Turns per conversation | 1 (single question → single answer) |
| Bbox coordinate space | `[0, 1000]` normalized xyxy |
| Refusal rate | ~6.5% (probes for honest "not present" answers) |

**What makes this benchmark hard**: every question requires the model to
jointly reason about *which* instrument, *where* it is (bbox), *what* it
is doing (verb), *to what* (target), and *when* (timestamp or window) —
often across multiple instruments simultaneously. The 30 templates test
these capabilities in isolation and in composition, from easy single-frame
lookups to hard multi-second temporal aggregations.

**Surgical domains**:
- **Cholecystectomy** (gallbladder removal) — laparoscopic, single camera,
  6 instrument classes, 10 verb classes, 15 target classes
- **Prostatectomy** (prostate removal) — robot-assisted, 7 instrument
  classes, 10 verb classes, 10 target classes

---

## 2. Task taxonomy

### 2.1 SpatioTemporal (10 templates)

These templates require the model to output or reason about bounding boxes
in the `[0, 1000]` coordinate space. Primary evaluation: IoU, center
distance, exact-match on instrument names.

---

#### `window` — Instrument presence windows (easy)

**Q**: "Which surgical instruments are visible between 5.00 s and 25.00 s?
For each instrument, provide its temporal presence window [start, end] in
seconds and its bounding box at the midpoint of that window."

**A**: "grasper: window [5.00 - 25.00], bbox at 15.00 s: {\"bbox_2d\":
[250, 180, 420, 380]}. hook: window [8.50 - 22.30], bbox at 15.40 s:
{\"bbox_2d\": [600, 150, 750, 320]}."

**Capability tested**: Multi-instrument temporal range detection + midpoint
spatial grounding. The model must enumerate *all* instruments in the window,
commit to each instrument's first/last appearance, and regress a bbox at a
specified timestamp.

**Metric**: Weighted composite — center distance (0.35) + temporal error
(0.25) + spatiotemporal error (0.40). Per-instrument, matched by name.

---

#### `locate` — Single-instrument localization (easy)

**Q**: "Locate the grasper at 12.75 s and provide its bounding box
[x1, y1, x2, y2] in normalized [0,1000] format."

**A**: "The grasper is located at {\"bbox_2d\": [180, 220, 380, 420]}."

**Capability tested**: Single-frame bbox regression given an instrument
name and timestamp. The simplest grounding task — a baseline for whether
the model can place a box at all.

**Metric**: Center distance score (1.0 weight).

---

#### `trajectory` — Extreme-position tracking (medium)

**Q**: "Trace the trajectory of the grasper between 5.50 s and 15.20 s.
Provide its most extreme left and right positions. Return ONLY:
Instrument: \<name\>, Window [start-end], Extreme Left: bbox at t=\<time\>,
Extreme Right: bbox at t=\<time\>."

**A**: "Instrument: grasper, Window [5.50 - 15.20], Extreme Left:
{\"bbox_2d\": [120, 300, 280, 480]} at t=6.25, Extreme Right:
{\"bbox_2d\": [680, 280, 840, 460]} at t=14.80."

**Capability tested**: The model must track one instrument across multiple
seconds, identify which frames produce the spatial extrema along a
specified axis, and output both the bbox AND the timestamp of each
extremum. Requires persistent identity tracking.

**Metric**: center (0.35) + temporal (0.25) + spatiotemporal (0.40).

**Challenge**: With only 4-8 sampled frames as input, the model may never
see the actual extremum frame — it must interpolate or extrapolate from
nearby frames.

---

#### `closest` — Nearest-instrument query (easy)

**Q**: "Which surgical instrument is closest to the point (0.48, 0.52)
at 8.90 s?"

**A**: "The grasper is the closest instrument to that point."

**Capability tested**: Spatial distance computation between a queried
2D point and multiple instrument bboxes. Requires the model to compare
distances across all visible instruments.

**Metric**: Label exact match (1.0 weight).

---

#### `rel_pos` — Relative position (medium)

**Q**: "Describe the relative position of the hook with respect to the
grasper at 10.30 s."

**A**: "The hook is located to the right and above the grasper."

**Capability tested**: Pairwise spatial reasoning — left/right and
above/below classification for two instruments at a single timestamp.

**Metric**: Horizontal accuracy (0.5) + vertical accuracy (0.5).

---

#### `rel_change` — Distance change over time (hard)

**Q**: "How does the distance between the grasper and the hook change
between 5.00 s and 15.00 s?"

**A**: "The grasper moved closer to the hook. (Distance change: -0.35.)"

**Capability tested**: Temporal comparison of inter-instrument distance
at two timepoints. The model must compute spatial distance at t1 AND t2,
then classify the delta as "closer / farther / approximately maintained"
and report the numeric delta.

**Metric**: Numeric relative error (0.5) + relation exact match (0.5).

**Challenge**: The "approximately maintained" class (|delta| < 0.30) is a
calibrated refusal — the model must know its own uncertainty.

---

#### `identify_bbox` — Inverse bbox lookup (easy)

**Q**: "Identify which surgical instrument is at bounding box
{\"bbox_2d\": [450, 250, 600, 400]} at 12.00 s."

**A**: "The scissors is located at that bounding box."

**Capability tested**: Given a bbox, name the instrument inside it. The
inverse of `locate`. Requires the model to match a region to a class label
when >=2 instrument classes are visible (otherwise trivial).

**Metric**: Label exact match (1.0 weight).

---

#### `locate_by_action` — Verb-grounded localization (medium)

**Q**: "At 18.50 s, provide the bounding box of the instrument performing
the action `dissect` in [0,1000] format."

**A**: "The instrument performing dissect is the hook, located at
{\"bbox_2d\": [280, 320, 480, 520]}."

**Capability tested**: Reverse grounding — given a verb, find which
instrument is performing it and localize it. Requires joint action
recognition + spatial grounding.

**Metric**: Center distance (1.0 weight), plus instrument name match.

---

#### `locate_by_target` — Target-grounded localization (medium)

**Q**: "At 22.00 s, locate the instrument interacting with the gallbladder
in [0,1000] format."

**A**: "The grasper is interacting with the gallbladder and is located at
{\"bbox_2d\": [350, 200, 520, 400]}."

**Capability tested**: Given an anatomical target, identify which instrument
is touching it and localize that instrument. Requires target recognition
(which is harder — targets are tissue, not distinct objects).

**Metric**: Center distance (1.0 weight), plus instrument name match.

---

#### `refusal_absent_instrument` — Negative evidence (medium)

**Q**: "Locate the irrigator at 8.50 s and provide its bounding box
[x1, y1, x2, y2] in normalized [0,1000] format."

**A**: "The irrigator is not present in this clip; no bounding box exists."

**Capability tested**: The question surface is **identical** to a real
`locate` question — the model must use video evidence (not question
phrasing) to decide the instrument is absent, then refuse rather than
hallucinate a bbox.

**Metric**: Refusal detection accuracy (exact match on refusal phrase).

**Challenge**: The question templates are intentionally indistinguishable
from `locate` / `locate_by_action` / `locate_by_target` questions. A model
that always produces a bbox will fail these.

---

### 2.2 MultiChoice (6 templates)

These are A/B/C/D multiple-choice questions. Primary evaluation: exact
match on the selected option letter.

---

#### `Classes` — Instrument set identification (easy)

**Q**: "Which types of surgical instruments are visible at 15.25 s?
A) grasper, hook B) grasper, scissors, hook C) scissors, clip D) hook, aspirator"

**A**: "Answer: A"

**Capability tested**: Multi-label instrument classification at a specific
timestamp. The model must recognize all visible instruments and match
against the distractor options (which are drawn from nearby timestamps in
the same clip for plausibility).

---

#### `Existence:global` — Clip-wide presence (easy)

**Q**: "Is the scissors present anywhere in this video clip? A) Yes B) No"

**Capability tested**: Global temporal scanning — the model must reason
over the entire clip, not just one frame.

---

#### `Existence:local_inst` — Frame-level instrument presence (easy)

**Q**: "Is the scissors visible at 5.50 s? A) Yes B) No"

**Capability tested**: Single-frame instrument detection.

---

#### `Existence:local_target` — Frame-level target presence (medium)

**Q**: "At 20.00 s, is the target gallbladder currently visible?
A) Yes B) No"

**Capability tested**: Anatomical target recognition — harder than
instrument detection because targets (tissues, organs) lack sharp visual
boundaries.

---

#### `Counting:distinct` — Class cardinality (medium)

**Q**: "How many distinct types of surgical tools are in the scene at
12.75 s? A) 1 B) 2 C) 3 D) 4"

**Capability tested**: Counting unique instrument classes (not instances).

---

#### `Counting:concurrent` — Peak concurrency (medium)

**Q**: "What is the maximum number of instruments visible simultaneously
between 10.00 and 20.00 s? A) 2 B) 3 C) 4 D) 5"

**Capability tested**: Temporal max-pooling of instrument count over a
multi-second window. Requires scanning multiple frames and reporting the
peak.

---

### 2.3 Interaction (14 templates)

These templates require understanding of action triplets
`(instrument, verb, target)` and their temporal structure. Primary
evaluation: per-subtask metrics aggregated via macro-average and
frequency-weighted average.

---

#### `target_interaction` — What target? (medium)

**Q**: "With what target is the grasper interacting from 8.50 to 12.30 s?"

**A**: "The grasper is interacting with the gallbladder."

**Capability tested**: Instrument-target binding over a temporal window.

---

#### `action_status` — What verb? (medium)

**Q**: "What is the grasper doing from 10.00 to 20.00 s?"

**A**: "The grasper is currently dissecting."

**Capability tested**: Verb classification over an extended window (>=10 s).

---

#### `next_action_target` — Action prediction (hard)

**Q**: "After the grasper finishes dissecting the gallbladder (ending at
~15.00 s), what does it transition to next?"

**A**: "After dissecting, the grasper transitions to **retracting** the
**liver**."

**Capability tested**: Sequential action prediction with a compound answer
(next verb + next target). The model must find the segment boundary and
identify the next action.

**Challenge**: Requires temporal boundary detection and anticipation.

---

#### `comparison` — Cross-instrument target comparison (hard)

**Q**: "Between 5.00 and 15.00 s, do the grasper and scissors interact
with the same target? Name the targets for both."

**A**: "No. The grasper interacts with the gallbladder and the scissors
interacts with the cystic duct."

**Capability tested**: Parallel tracking of two instruments' targets and
comparison. Multi-atom scoring: same/different verdict + both target names.

---

#### `reverse_target` — Target-to-instruments reverse lookup (medium)

**Q**: "Are any instruments interacting with the gallbladder between
8.50 and 18.00 s?"

**A**: "Yes: grasper, hook."

**Capability tested**: Given a target, enumerate all instruments acting on
it. The inverse of `target_interaction`.

---

#### `interaction_duration` — Cumulative time on an action (medium)

**Q**: "How many seconds does the grasper spend grasping the gallbladder?"

**A**: "The grasper grasps the gallbladder for 5.75 s across 3 segments."

**Capability tested**: Temporal aggregation — sum durations of all segments
matching a (verb, target) pair. The model must count segments AND accumulate
their durations.

---

#### `longest_continuous_action` — Max-duration segment (hard)

**Q**: "What is the longest continuous stretch of the hook dissecting?"

**A**: "The longest continuous dissection segment is 28.50 seconds."

**Capability tested**: Find the single longest segment among potentially
many non-contiguous occurrences of the same verb.

---

#### `idle_duration` — Idling ratio (medium)

**Q**: "What percentage of the clip does the grasper spend idling?"

**A**: "The grasper idles for 12.50 s, which is 20.8% of the clip."

**Capability tested**: Idling detection (absence of any verb) + ratio
computation.

---

#### `first_appearance_time` / `last_appearance_time` — Temporal edges (easy)

**Q**: "When does the grasper first appear?" / "When does it last appear?"

**A**: "The grasper first appears at 2.50 s." / "...last appears at 55.80 s."

**Capability tested**: Earliest/latest temporal detection.

---

#### `action_sequence` — Chronological action list (hard)

**Q**: "List all (verb, target) interactions of the grasper in order."

**A**: "(2.50 s) grasping gallbladder → (8.80 s) dissecting gallbladder →
(15.20 s) grasping cystic-duct → (22.50 s) retracting peritoneum"

**Capability tested**: Full temporal action parsing — the model must
reconstruct the entire action timeline for one instrument. Evaluated via
sequence matching (ROUGE-L / BLEU).

**Challenge**: The hardest interaction template. Requires persistent
instrument tracking + segment boundary detection + verb + target
classification at every transition.

---

#### `dominant_verb` — Most-frequent action (medium)

**Q**: "Which verb consumes the most cumulative time across all instruments?"

**A**: "The dominant verb is dissecting."

**Capability tested**: Temporal aggregation by verb class, ranked.

---

#### `distinct_targets_touched` — Target set cardinality (medium)

**Q**: "How many distinct anatomical targets are involved in any action?"

**A**: "4 targets: gallbladder, cystic-artery, cystic-duct, peritoneum."

**Capability tested**: Set cardinality across the entire clip timeline.

---

#### `refusal_no_specific_action` — Idling refusal (easy)

**Q**: "At 8.50 s (+/-2 s tolerance), what specific action is the grasper
performing?"

**A**: "The grasper is currently idling — no specific verb is being
performed in the window from 6.50 to 10.50 s."

**Capability tested**: Honest refusal when an instrument is visible but not
performing any action. Analogous to `refusal_absent_instrument` but for the
action dimension.

---

## 3. Vocabulary and label space

### 3.1 Instruments

| ID | Cholecystectomy | ID | Prostatectomy |
|---:|---|---:|---|
| 0 | grasper | 0 | Endobag |
| 1 | bipolar | 1 | aspirator |
| 2 | hook | 2 | clip applier |
| 3 | scissors | 3 | forceps |
| 4 | clipper | 4 | grasper |
| 5 | irrigator | 5 | needle driver |
| | | 6 | scissors |

### 3.2 Verbs (actions)

| ID | Cholecystectomy | ID | Prostatectomy |
|---:|---|---:|---|
| 0 | grasp | 0 | bag |
| 1 | retract | 1 | clip |
| 2 | dissect | 2 | coagulate |
| 3 | coagulate | 3 | cut |
| 4 | clip | 4 | dissect |
| 5 | cut | 5 | grasp |
| 6 | aspirate | 6 | null_verb (idling) |
| 7 | irrigate | 7 | retract |
| 8 | pack | 8 | suck |
| 9 | null_verb (idling) | 9 | suture |

### 3.3 Targets (anatomical structures)

| ID | Cholecystectomy | ID | Prostatectomy |
|---:|---|---:|---|
| 0 | gallbladder | 0 | Endobag |
| 1 | cystic-plate | 1 | bladder |
| 2 | cystic-duct | 2 | catheter |
| 3 | cystic-artery | 3 | fascias |
| 4 | cystic-pedicle | 4 | fluid |
| 5 | blood-vessel | 5 | gauze |
| 6 | fluid | 6 | null_target |
| 7 | abdominal-wall/cavity | 7 | prostate |
| 8 | liver | 8 | seminal-vesicle |
| 9 | adhesion | 9 | thread |
| 10 | omentum | | |
| 11 | peritoneum | | |
| 12 | gut | | |
| 13 | specimen-bag | | |
| 14 | null_target | | |

---

## 4. Input / output format

### 4.1 Conversation JSON (one file per QA)

```json
{
  "video": "/absolute/path/to/cholec_02_141_166.mp4",
  "category": "SpatioTemporal",
  "subcategory": "locate",
  "difficulty": "easy",
  "conversations": [
    {
      "from": "human",
      "value": "<video>\nLocate the grasper at 12.75 s and provide its bounding box [x1, y1, x2, y2] in normalized [0,1000] format."
    },
    {
      "from": "gpt",
      "value": "The grasper is located at {\"bbox_2d\": [180, 220, 380, 420]} (normalized [0,1000] format)."
    }
  ]
}
```

- `<video>` token appears **only** in the first human turn
- Bboxes in text use `{"bbox_2d": [x1, y1, x2, y2]}` in `[0, 1000]` range
- Any question involving bboxes includes the instruction: "Return all
  bounding box coordinates in normalized [0,1000] format."

### 4.2 Video frame sampling (default training config)

| Parameter | Value |
|---|---|
| Sample FPS | 2 fps |
| Min frames per clip | 4 |
| Max frames per clip | 8 |
| Min pixels | 128 x 28 x 28 = 100 352 |
| Max pixels | 384 x 28 x 28 = 301 056 |

A 25-second clip at 2 fps yields **8 frames** (the max). Each frame is
resized to fit within the pixel budget. The model therefore sees
**a sparse temporal sample** — most of the 15 fps clip is never seen.

**Architectural implication**: any model that needs to answer timestamp
questions (e.g., "at 12.75 s") must map between the queried timestamp and
the nearest sampled frame. With 8 frames covering 25 seconds, the
worst-case gap is ~3 s. Templates like `trajectory` and `rel_change`
require reasoning about motion between sampled frames.

### 4.3 System prompt

```
You are an AI assistant specializing in the analysis of surgical scenes
of minimally invasive procedures. Each surgical instrument's position in
the video as well as the corresponding verb and target it is interacting
with is represented as a tuple:
(fn, c_i, x1, x2, y1, y2, c_v, c_t, phase, step), where c_i is the
unique identifier for the surgical instrument.
fn is the normalized timestamp of the frame (a float between 0 and 1).
x1, x2, y1, y2 are the normalized coordinates of the bounding box.
c_v is the verb class (action). c_t is the target class (tissue/object).
```

### 4.4 Label masking

During supervised fine-tuning, only the assistant (gpt) turns contribute
to the loss. User turns and system prompts are masked with `IGNORE_INDEX
= -100`.

---

## 5. Evaluation protocol

### 5.1 Per-category primary metrics

| Category | Primary metric | Description |
|---|---|---|
| MultiChoice | `accuracy` | Exact match on parsed "Answer: X" |
| SpatioTemporal | `subtask_weighted_primary` | Per-subtask primary (IoU, label match, relative error) weighted by template frequency |
| Interaction | `subtask_weighted_primary` | Per-subtask primary (exact match, numeric error, sequence match) weighted by template frequency |

### 5.2 SpatioTemporal subtask weights

| Subtask | Primary composition | Aggregation weight |
|---|---|---|
| `window` | center (0.35) + temporal (0.25) + spatiotemporal (0.40) | 1.0 |
| `locate` | center distance (1.0) | 1.0 |
| `trajectory` | center (0.35) + temporal (0.25) + spatiotemporal (0.40) | 1.0 |
| `closest` | label exact match (1.0) | 0.8 |
| `rel_pos` | horizontal (0.5) + vertical accuracy (0.5) | 1.0 |
| `rel_change` | numeric (0.5) + relation label (0.5) | 1.0 |
| `identify_bbox` | label exact match (1.0) | 1.0 |
| `locate_by_action` | center distance (1.0) | 1.0 |
| `locate_by_target` | center distance (1.0) | 1.0 |
| `refusal_absent_instrument` | refusal detection (1.0) | 1.0 |

### 5.3 Interaction subtask metrics

Each interaction subtask has its own parser + scoring function. Examples:
- `target_interaction` / `action_status` / `dominant_verb`: exact name match
- `interaction_duration` / `longest_continuous_action`: numeric relative error
- `comparison`: multi-atom (same/different verdict + both target names)
- `action_sequence`: sequence alignment (token F1 / ROUGE-L)

### 5.4 Macro average

```
macro_primary = mean(MultiChoice/accuracy,
                     SpatioTemporal/subtask_weighted_primary,
                     Interaction/subtask_weighted_primary)
```

### 5.5 Refusal-rate audit

Refusal templates (`refusal_absent_instrument`,
`refusal_no_specific_action`) are tracked separately: ~6.5% of all
conversations. A model that always answers positively will fail these
silently — the audit catches it.

---

## 6. Metadata: the Event Tuple

The generators consume an internal representation per clip:

```
(t_sec, c_i, inst_id, x1, x2, y1, y2, c_v, c_t)
```

| Field | Type | Description |
|---|---|---|
| `t_sec` | float | Wall-clock seconds in the original source video |
| `c_i` | int | Instrument class id |
| `inst_id` | int | Per-clip persistent instance id (distinguishes two same-class instruments) |
| `x1, x2` | float | Bbox x-range, normalized by frame width (xx order) |
| `y1, y2` | float | Bbox y-range, normalized by frame height (yy order) |
| `c_v` | int | Verb class id (-1 = idling) |
| `c_t` | int | Target class id (-1 = no target) |

**Instance id**: Two graspers in the same clip get `inst_id=0` and
`inst_id=1`. The id is persistent across the clip (greedy nearest-centroid
tracker). This enables multi-instance templates like `comparison` where
two same-class instruments must be distinguished.

**Continuity gates**: Trajectory and rel_change templates require the
target instrument to be continuously tracked (max displacement 0.6
normalized-diag/sec, max temporal gap 0.7 s between samples).

---

## 7. Architectural desiderata

Based on the task analysis above, a VLM that performs well on SurgSTU needs:

### 7.1 Fine-grained temporal grounding

26 of 30 templates reference specific timestamps or windows. The model
must map a queried time (e.g., "at 12.75 s") to the correct video frame
despite seeing only 4-8 sparse samples. **Implication**: timestamp-aware
positional embeddings or an explicit frame-timestamp association mechanism.
Models that treat video as an unordered bag of frames will fail.

### 7.2 Spatial grounding with bbox regression

10 templates require `[0, 1000]` bbox output. The model must generate
numeric coordinates as text tokens. **Implication**: the language head
must be able to produce precise 3-4 digit numbers, not just natural
language. Tokenization of numbers matters — a model that tokenizes "428"
as ["4", "28"] will have different learning dynamics than one that
tokenizes it as ["428"].

### 7.3 Multi-instance disambiguation

Same-class instruments coexist frequently (e.g., two graspers).
Templates like `comparison`, `trajectory`, and `rel_pos` require
distinguishing "grasper on the left" from "grasper on the right".
**Implication**: the visual encoder must support instance-level features,
not just class-level detection. Attention patterns that pool over all
instances of a class will lose this signal.

### 7.4 Compositional action understanding

Every action is a triplet: (instrument, verb, target). The model must bind
these correctly — "the hook is dissecting the gallbladder" is a different
fact from "the hook is dissecting the cystic-duct" or "the grasper is
dissecting the gallbladder". **Implication**: structured relation
representations (graph-based or slot-based) may outperform flat feature
vectors.

### 7.5 Temporal aggregation over multi-second windows

Templates like `interaction_duration`, `action_sequence`,
`longest_continuous_action`, `idle_duration`, and `dominant_verb` require
the model to aggregate information across 10-30 seconds of video.
**Implication**: a model limited to per-frame reasoning cannot answer
these. It needs either (a) a temporal integration mechanism (temporal
attention, state tracking, or recurrence), or (b) enough context length
to attend to all sampled frames jointly.

### 7.6 Calibrated refusal

2 templates (6.5% of corpus) require the model to say "not present" or
"no action" when the evidence genuinely doesn't support a positive answer.
**Implication**: the model must have a calibrated confidence mechanism.
Architectures that always force a positive answer (e.g., through beam
search that penalizes empty responses) will leak performance on these
probes.

### 7.7 Numeric precision

Trajectory coordinates, duration estimates, and distance deltas are
evaluated via relative error. A model that outputs "about 10 seconds"
when the answer is 12.5 s gets a 20% relative error. **Implication**: the
model must treat numeric generation as a first-class output mode, not an
afterthought of the language head.

### 7.8 Cross-domain generalization

The two surgical procedures have different instruments, different
anatomical targets, different camera setups (laparoscopic vs robotic), and
different visual characteristics. A model trained on both must generalize
the underlying spatial-temporal reasoning across domains, not just memorize
procedure-specific patterns. **Implication**: shared backbone with
procedure-specific vocabulary projection, or other domain-adaptation
strategies.

---

## 8. Current corpus statistics

### 8.1 Per-template sample counts (Phase 5e, post-VID31 exclusion)

| Procedure | Category | Subcategory | Difficulty | n |
|---|---|---|---|---:|
| cholec | MultiChoice | Classes | easy | 874 |
| cholec | MultiChoice | Counting:concurrent | medium | 864 |
| cholec | MultiChoice | Counting:distinct | medium | 874 |
| cholec | MultiChoice | Existence:global | easy | 874 |
| cholec | MultiChoice | Existence:local_inst | easy | 874 |
| cholec | MultiChoice | Existence:local_target | medium | 874 |
| cholec | SpatioTemporal | closest | easy | 636 |
| cholec | SpatioTemporal | identify_bbox | easy | 317 |
| cholec | SpatioTemporal | locate | easy | (part of 874 pool) |
| cholec | SpatioTemporal | refusal_absent_instrument | medium | 868 |
| cholec | SpatioTemporal | rel_change | hard | 25 |
| cholec | SpatioTemporal | rel_pos | medium | 554 |
| cholec | SpatioTemporal | trajectory | medium | (part of pool) |
| cholec | SpatioTemporal | window | easy | (part of pool) |
| cholec | SpatioTemporal | locate_by_action | medium | (part of pool) |
| cholec | SpatioTemporal | locate_by_target | medium | (part of pool) |
| cholec | Interaction | action_sequence | hard | 55 |
| cholec | Interaction | action_status | medium | 539 |
| cholec | Interaction | comparison | hard | 255 |
| cholec | Interaction | distinct_targets_touched | medium | 395 |
| cholec | Interaction | dominant_verb | medium | 317 |
| cholec | Interaction | first_appearance_time | easy | 76 |
| cholec | Interaction | idle_duration | medium | 49 |
| cholec | Interaction | interaction_duration | medium | 25 |
| cholec | Interaction | last_appearance_time | easy | 9 |
| cholec | Interaction | longest_continuous_action | hard | 398 |
| cholec | Interaction | next_action_target | hard | (part of pool) |
| cholec | Interaction | refusal_no_specific_action | easy | 46 |
| cholec | Interaction | reverse_target | medium | 874 |
| cholec | Interaction | target_interaction | medium | 660 |
| prosta | MultiChoice | Classes | easy | 928 |
| prosta | MultiChoice | Counting:concurrent | medium | 928 |
| prosta | MultiChoice | Counting:distinct | medium | 928 |
| prosta | MultiChoice | Existence:global | easy | 928 |
| prosta | MultiChoice | Existence:local_inst | easy | 928 |
| prosta | MultiChoice | Existence:local_target | medium | 928 |
| prosta | SpatioTemporal | closest | easy | 928 |
| prosta | SpatioTemporal | identify_bbox | easy | 834 |
| prosta | SpatioTemporal | refusal_absent_instrument | medium | 928 |
| prosta | SpatioTemporal | rel_change | hard | 63 |
| prosta | SpatioTemporal | rel_pos | medium | 876 |
| prosta | Interaction | action_sequence | hard | 587 |
| prosta | Interaction | action_status | medium | 825 |
| prosta | Interaction | comparison | hard | 722 |
| prosta | Interaction | distinct_targets_touched | medium | 708 |
| prosta | Interaction | dominant_verb | medium | 727 |
| prosta | Interaction | first_appearance_time | easy | 79 |
| prosta | Interaction | idle_duration | medium | 661 |
| prosta | Interaction | interaction_duration | medium | 300 |
| prosta | Interaction | last_appearance_time | easy | 71 |
| prosta | Interaction | longest_continuous_action | hard | 748 |
| prosta | Interaction | refusal_no_specific_action | easy | 551 |
| prosta | Interaction | reverse_target | medium | 928 |
| prosta | Interaction | target_interaction | medium | 885 |

### 8.2 Difficulty distribution

| Difficulty | Count | Share |
|---|---:|---:|
| easy | ~12 000 | ~37% |
| medium | ~15 000 | ~46% |
| hard | ~5 800 | ~18% |

### 8.3 Refusal rate

| Procedure | Total | Refusal samples | Refusal share |
|---|---:|---:|---:|
| cholec | 14 328 | 914 | 6.4% |
| prosta | 21 253 | 1 479 | 7.0% |

---

## 9. Evaluation tooling

### 9.1 Unified evaluation script: `evaluate_surgstu.py`

The canonical way to score any VLM's predictions against SurgSTU ground
truth. Supersedes the older `recalculate_results_metrics.py` and
`recalculate_core_task_scores.py`.

```bash
# Score a single results file (prints Markdown tables to stdout)
python evaluate_surgstu.py --input output/results_model_a.json

# Compare multiple models side-by-side
python evaluate_surgstu.py --input "output/results_*.json"

# Write rescored JSON (per-sample metrics injected into each record)
python evaluate_surgstu.py --input output/results.json --output-json rescored.json

# Write Markdown report to file
python evaluate_surgstu.py --input output/results.json --output-md report.md
```

**Input contract** — a JSON file with a `"records"` list:

```json
{
  "records": [
    {
      "prediction": "The grasper is located at {\"bbox_2d\": [180, 220, 380, 420]}",
      "ground_truth": "The grasper is located at {\"bbox_2d\": [190, 215, 385, 425]}",
      "category": "SpatioTemporal",
      "subcategory": "locate",
      "sample_id": "cholec_02_141_166_locate_001"
    }
  ]
}
```

Required fields per record: `prediction`, `ground_truth`, `category`,
`subcategory`. All other fields (`sample_id`, `video_path`, ...) are
optional and passed through.

**Output layers** (all printed to stdout as Markdown):

1. **Per-template scores** — one row per (category, subcategory), showing
   sample count and the template's primary metric score.
2. **Core-task scores** — the 30 templates grouped into 6 high-level
   capability buckets (see §9.2), micro-averaged.
3. **Per-category summary** — MultiChoice accuracy, SpatioTemporal
   primary, Interaction primary, and overall macro-average.
4. **Per-procedure breakdown** — cholec vs prosta scores per category.
5. **Model comparison table** (multi-file mode) — one row per model,
   sorted by macro-average.

### 9.2 Core-task taxonomy (6 capability groups)

The 30 templates map to 6 high-level tasks that an architecture designer
can target independently:

| Core Task | Templates | What it measures |
|---|---|---|
| **Spatial-Temporal Grounding** | window, locate, trajectory, closest, identify_bbox, locate_by_action, locate_by_target | Bbox regression + instrument naming at specific timestamps |
| **Spatial-Temporal Relations** | rel_pos, rel_change, comparison | Pairwise spatial reasoning between instruments (position, distance, target overlap) |
| **Interaction Captioning** | target_interaction, action_status, next_action_target, reverse_target, action_sequence | Verb-target binding + temporal action parsing |
| **Temporal Aggregation** | interaction_duration, longest_continuous_action, idle_duration, first/last_appearance_time, dominant_verb, distinct_targets_touched | Duration estimation, counting, ranking over multi-second windows |
| **Multi-Choice QA** | Classes, Existence (global/local_inst/local_target), Counting (distinct/concurrent) | Instrument recognition + cardinality + existence reasoning |
| **Calibrated Refusal** | refusal_absent_instrument, refusal_no_specific_action | Honest "not present" / "no action" when evidence doesn't support a positive answer |

### 9.3 Metrics engine: `evaluation/metrics.py`

All scoring logic lives in this module. The unified script calls
`compute_all_metrics(predictions, references, categories, subcategories)`
which dispatches per-category:

| Category | Primary metric | How it works |
|---|---|---|
| MultiChoice | `accuracy` | Exact match on parsed "Answer: X" letter |
| SpatioTemporal | `subtask_weighted_primary` | Per-subtask composite (IoU, center distance, temporal error, label match) weighted by template frequency |
| Interaction | `subtask_weighted_primary` | Per-subtask metrics (exact match, numeric relative error, sequence alignment) weighted by template frequency |
| **Overall** | `macro_average` | Unweighted mean of the 3 category primaries |

**SpatioTemporal subtask primary composition**:

| Subtask | Components | Weights |
|---|---|---|
| window, trajectory | center distance + temporal error + spatiotemporal error | 0.35 + 0.25 + 0.40 |
| locate, locate_by_action, locate_by_target | center distance | 1.0 |
| closest, identify_bbox | label exact match | 1.0 |
| rel_pos | horizontal accuracy + vertical accuracy | 0.5 + 0.5 |
| rel_change | numeric relative error + relation label match | 0.5 + 0.5 |
| refusal_absent_instrument | refusal detection | 1.0 |

**Bbox parsing**: the metrics engine uses 6 regex patterns to extract
`[x1, y1, x2, y2]` from model output — handles `{"bbox_2d": [...]}`,
`bbox = (...)`, bare `[...]`, and `<...>` formats. IoU is computed in
the `[0, 1000]` coordinate space.

### 9.4 Baseline results (Qwen3-VL 2B)

From the existing results files, scored via `evaluate_surgstu.py`:

| Model | MC | ST | Inter | Macro |
|---|---:|---:|---:|---:|
| Qwen3-VL 2B LoRA fine-tune | 0.918 | 0.595 | 0.613 | **0.709** |
| Qwen3-VL 2B zero-shot (ICL) | 0.534 | 0.380 | 0.316 | 0.410 |

**Per-core-task (fine-tuned model)**:

| Core Task | n | Primary |
|---|---:|---:|
| Multi-Choice QA | 9 911 | 0.905 |
| Interaction Captioning | 4 914 | 0.639 |
| Spatial-Temporal Grounding | 8 116 | 0.577 |
| Spatial-Temporal Relations | 4 193 | 0.519 |

**Per-procedure (fine-tuned)**:

| Procedure | MC | ST | Interaction |
|---|---:|---:|---:|
| cholec | 0.939 | 0.657 | 0.674 |
| prosta | 0.897 | 0.540 | 0.558 |

**Key gap analysis for architecture designers**:
- **Multi-Choice is nearly saturated** (0.918) — little room for
  architectural improvement; the bottleneck is elsewhere.
- **SpatioTemporal is the main opportunity** (0.595) — bbox regression and
  temporal grounding are far from solved. The hardest subtasks are
  `window` (0.416, requires multi-instrument temporal windowing + bbox at
  midpoint), `rel_change` (0.384, distance comparison across time), and
  `identify_bbox` (0.434, inverse bbox lookup with disambiguation).
- **Interaction captioning is moderate** (0.613) — `target_interaction`
  (0.395) and `comparison` (0.372) lag, suggesting the model struggles with
  fine-grained instrument-target binding when multiple instruments are
  active.
- **Cholec consistently outperforms Prosta** (+5-12 pp per category),
  likely because cholec has higher-confidence bboxes (manual CT20
  annotations) and a smaller instrument vocabulary (6 vs 7 classes).
- **Zero-shot → fine-tuned jump is 0.410 → 0.709** (+73% relative),
  confirming that SurgSTU requires domain-specific training — general
  VLMs cannot solve it out of the box.

---

## 10. Key files reference

| File | Purpose |
|---|---|
| `evaluate_surgstu.py` | **Unified evaluation CLI** (score predictions, compare models) |
| `evaluation/metrics.py` | Core metrics engine (IoU, exact match, relative error, etc.) |
| `utils/data/create_surgSTU_qa_dataset.py` | Stage 2: all 30 QA generators + orchestrator |
| `utils/data/generate_tuple_format_for_metadata.py` | Stage 1.5: per-clip metadata.txt |
| `data/__init__.py` | Dataset registry and split paths |
| `data/data_processor.py` | Video frame sampling + collation |
| `utils/data/qa_templates.py` | System prompt (reference only) |
| `train_qwen.py` | Training entry point |
| `run_test.py` | Inference + scoring pipeline (runs a model end-to-end) |
