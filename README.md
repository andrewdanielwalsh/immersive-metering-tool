# Immersive Metering Tool

A MATLAB-based immersive audio metering and room-analysis app for WAV files and speaker-layout review.

The app is designed for practical inspection of immersive audio files while also providing a configurable room model for speaker placement, arrival-time, and delay calculations.

---

## Main Features

- Load mono, stereo, 4.0 / quad, 5.1, 7.1, 7.1.2, and 7.1.4 WAV files.
- Analyze levels and loudness.
- Display a 3D spectrogram.
- Display a spatial-field view.
- Calculate speaker distance, arrival time, and delay-to-add values.
- Support automatic Dolby-style speaker placement defaults.
- Support manual listener-position override.
- Support manual speaker distance override.
- Support manual speaker X/Y/Z position override.
- Use X/Y/Z override as the highest-priority manual speaker placement method.
- Keep room setup independent from WAV analysis unless match mode is enabled.

---

## Requirements

### Required Software

- MATLAB
- MATLAB App/UI support through `uifigure`, `uiaxes`, `uitable`, `uidropdown`, and related UI components

### MATLAB Toolboxes

The app is written to use standard MATLAB UI and audio functions. Depending on your local analysis functions, the following may be required:

- MATLAB base audio I/O support:
  - `audioread`
  - `audioinfo`
- Signal Processing Toolbox may be required by your spectrogram or analysis helper functions if they use functions such as `spectrogram`, windowing utilities, or filtering tools.

If a helper function requires a toolbox that is not installed, MATLAB will show an error in the app Status box or Command Window.

---

## How to Start the App

From the MATLAB Command Window, run:

	clear functions
	clear classes
	app = ImmersiveMeteringAppLite;


Or right-click on ImmersiveMeteringAppLite.m and select **Run**

---

## Basic Workflow

### 1. Start the app

### 2. Set up the room, if needed

Room setup can be used with or without a loaded WAV file.

In the Room Setup panel:

1. Choose the room format.
2. Enter room length, width, and height.
3. Click **Update Room**.

The Room tab will display:

- Room boundary
- Listener position
- Speaker positions
- Speaker label and distance

The Room table displays:

- Speaker
- Group
- Distance
- X/Y/Z
- Within-room status
- Azimuth
- Elevation
- Placement status
- Placement note

### 3. Load a WAV file

Click **Load WAV**.

Loading a WAV does only this:

- Reads the WAV file.
- Displays basic file information in the Status and Summary areas.
- Suggests an audio format based on channel count.
- Updates the analysis channel map.

Loading does **not** run analysis automatically.

* Note: Three sample WAV files of diffrent audio formats are included in Zip.

### 4. Analyze the WAV file

Click **Analyze WAV**.

This runs:

- Level analysis
- Loudness analysis
- Spectrogram update
- Spatial-field update

### 5. Review results

Use the main tabs:

 - Spectrogram
 - Spatial Field
 - Levels / Loudness
 - Room
 - Speaker Delays

---

## Room Setup

The room model is independent from the WAV file by default.

### Match Room Format to Loaded WAV

The Room Setup panel includes:

Match Room Format to Loaded WAV

When unchecked:

- The room format is independent.
- Loading a WAV does not change the room model.
- You can design/check a playback room separately from the file.

When checked:

- The room format follows the loaded WAV format.
- Loading a WAV can update the room format.
- Use this when you want the room speaker layout to match the file channel count.

---

## Advanced Room Setup

The Advanced Room Setup section supports manual overrides.

### Manual Listener Position

Enable **Manual Listener Position** to enter:

- Listener X
- Listener Y
- Listener Z

Coordinate convention:

X = room width
Y = room length
Z = height

The listener is normally generated automatically from the room dimensions.

### Manual Speaker Overrides

Enable **Use Manual Speaker Overrides** to manually override speaker placement.

For each selected speaker, you can enter either:

- Manual distance
- Manual X/Y/Z position

Priority:

Manual X/Y/Z overrides manual distance.
Manual distance overrides generated placement.
Generated placement is used when no manual override is enabled.

---

## Speaker Delays

The Speaker Delays tab is table-only.

Visible columns:

 - Speaker
 - ArrivalTime_ms
 - DelayToAdd_ms
 - TimingRole
 - ManualPlacementUsed
 - DelayNote

### ArrivalTime_ms

The time required for sound to travel from the speaker to the listener.

ArrivalTime_ms = distance / speed of sound × 1000

### DelayToAdd_ms

The delay that should be added to that speaker so it aligns with the latest-arriving speaker.

DelayToAdd_ms = reference arrival time - speaker arrival time

### TimingRole

Indicates whether a speaker is the timing reference or should be delayed to match the reference.

Possible values:

 - Reference / Latest Arrival
 - Delay to Match Reference

### ManualPlacementUsed

Indicates whether a manual placement override affected the speaker.

Possible values:

 - No
 - Manual Distance
 - Manual X/Y/Z

---

## Levels / Loudness Tab

The Levels / Loudness tab summarizes the signal level and perceived loudness of the loaded WAV file.

The Levels table shows technical metering values such as peak level, RMS level, and crest factor for each channel.

The Loudness table shows loudness measurements such as integrated LUFS for program and channel-level review. 

	* Note - The user-facing Levels / Loudness tables are intentionally cleaned up.

	Hidden from the main display:

	- DC offset
	- Clip percentage
	- Silent percentage
	- Linear peak
	- Linear RMS
	- True peak dB
	- Internal short diagnostic ratio columns such as `PSR_dB`, `PLR_dB`, `PRS_dB`, etc.

---

## Spectrogram

The Spectrogram tab displays the selected source as a 3D plot.

Controls:

- Source
- Start time
- Duration
- FFT window
- Overlap
- Low frequency
- High frequency

Click **Update Spectrogram** to refresh only the spectrogram.

---

## Spatial Field

The Spatial Field tab displays the movement or concentration of energy across the speaker layout.

When a room model exists, the spatial field can be plotted in room coordinates using meters.

Recommended workflow:

1. Update Room
2. Load WAV
3. Analyze WAV

This allows the spatial field to use the room layout rather than only normalized coordinates.

---

## Supported Audio Formats

The app supports these format options:

 - mono
 - stereo
 - 4.0
 - 5.1
 - 7.1
 - 7.1.2
 - 7.1.4

The app can suggest a format based on WAV channel count:

 - 1 channel  -> mono
 - 2 channels -> stereo
 - 4 channels -> 4.0
 - 6 channels -> 5.1
 - 8 channels -> 7.1
 - 10 channels -> 7.1.2
 - 12 channels -> 7.1.4


---

## Channel Mapping

Channel mapping is handled through format helper functions when available:

 - getFormatMap.m
 - validateChannelMap.m

If those are unavailable or fail, the app uses internal fallback mapping so it can continue running.

The user-facing Summary no longer displays the fallback mapping warning row.

---

## Recommended Folder Structure

Keep the project in one main folder, for example:


ImmersiveMeteringTool/
├── ImmersiveMeteringAppLite.m
├── README.md
├── room/
│   ├── defaultRoomModel.m
│   └── attachSpeakerPlacementEvaluation.m
├── plotting/
│   ├── plotSpectrogram3D.m
│   ├── plotSoundField3D.m
│   └── plotRoomLayout3D.m
├── WAVs/
│   ├── Scrapped - 7.1.wav
│   ├── 06 When Music Sounds - Petkovski.wav
│   └── 01 Exsultate justi - Hakenberge.wav
├── analysis/
│   ├── computeLevels.m
│   ├── computeLoudness.m
│   ├── computeSpectrogram3D.m
│   └── computeSpatialEnergy.m
└── formats/
    ├── getFormatMap.m
    └── validateChannelMap.m



Your exact folder names may differ. The app adds the project folder and subfolders to the MATLAB path at startup using `addpath(genpath(...))`.

---

## Important Files

### Main app

 - ImmersiveMeteringAppLite.m

	Main class-based MATLAB app.

### Room model

 - defaultRoomModel.m

	Builds speaker positions, distances, delay values, and placement notes.

 - attachSpeakerPlacementEvaluation.m

	Compatibility wrapper for placement table/status generation.

### Audio analysis

 - computeLevels.m
 - computeLoudness.m
 - computeSpectrogram3D.m
 - computeSpatialEnergy.m

	Analysis backend for the main app.

### Plotting

 - plotSpectrogram3D.m
 - plotSoundField3D.m
 - plotRoomLayout3D.m
	
	Ploting backend for the main app.

---

## Known Limitations

- The room model is a Dolby-style practical implementation, not a certified replacement for Dolby DARDT.
- Speaker placement is based on target angles, room dimensions, and practical constraints.
- Very small rooms may force speaker positions to be clamped or marked for review.
- Spatial-field behavior depends on channel mapping and available room model data.
- MATLAB Online may show slower plot interaction for large WAV files or complex 3D plots.
