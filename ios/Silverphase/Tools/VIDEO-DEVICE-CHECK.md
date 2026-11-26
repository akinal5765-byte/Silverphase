# Video device check

This draft exposes a separate, device-configured SDR HEVC rear-camera recorder in Library → ⋯ →
Record Video in Debug only, until device acceptance. It has no application recording-duration cap. Recording stays in
the foreground, with sound; interruptions end the current take rather than
trying to resume into the same file. Capture quality, thermal behavior, and
export speed are not yet validated on iPhone.

The hardware writes a QuickTime source; the separate post-capture pass uses the
selected film's normal print/scan workflow through the native Metal engine,
one frame at a time. It preserves the audio track and has no app-imposed limit
on the source length. Automatic Maximum takes the largest available raster
for the selected physical rear lens, then the fastest frame rate at that
raster, based on the lens's AVFoundation movie-compatible SDR formats.
Turn Automatic off to pick resolution and then one of its supported rates.
Changing lenses preserves the existing manual pair only if the new lens
offers it. Otherwise the app asks for a new pair. The configured dimensions
and frame rate are shown before recording. The post-recording player previews the ungraded original and names the film
for the explicit Apply Film and Save action. Saving the original does not
apply a film. No silent fallback on setup,
capture, or export failure. The live viewfinder is ungraded. Glare and per-frame film
auto-metering are intentionally off in this first version. The still, Portrait,
camera shortcut and lock-screen routes keep their own camera configuration. Live
Photo and real-time graded recording are not part of this change.

## Build

```sh
python3 ios/Silverphase/Tools/gen-project.py --check
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
  SILVERPHASE_LOCAL_MATERIALS=0 xcodebuild -project ios/Silverphase/Silverphase.xcodeproj \
  -scheme Silverphase -configuration Debug -sdk iphonesimulator \
  -derivedDataPath /tmp/silverphase-video-derived CODE_SIGNING_ALLOWED=NO build
```

Use the installed Apple SDK/Metal toolchain and a signed physical iPhone build
for the rest, ideally an older supported device and a current one.

## Repeatable export smoke check (Debug)

Use a dedicated test app container. Put a short BT.709 HEVC MOV with audio in
its Documents directory under one or more of these names:

- `video-check-uhd30-landscape.mov` and `video-check-uhd30-portrait.mov`
- `video-check-uhd60-landscape.mov` and `video-check-uhd60-portrait.mov`
- `video-check-legacy-small.mov` for a smaller historical input (no UHD claim)

Launch with `--video-format-regression` for ranking, rational frame rates,
legacy metadata and rotation-normalized dimensions. It writes `video-format-report.json`.
Launch with `--video-export-regression` for capture-format and export checks. The app writes
`video-export-report.json` and, for each successful conversion, a
`video-check-…-developed.mov` beside its source without saving to Photos.
Run the pair checker on the files to check real presentation timestamps and
SDR tags. Use portrait display metadata as well as a landscape fixture.
For a Photos-write regression separate from film rendering, grant add-only
Photos permission in a dedicated simulator, inject `video-check-legacy-small.mov`,
then launch with `--video-photos-regression`. Verify `video-photo-save-report.json`
reports `saved` and the source remains. This test writes one synthetic video
to the simulator's library; it is not active on physical devices.

For a content check, inject a saturated, short 640×360 BT.709 fixture with
audio under the same legacy fixture name and launch with
`--video-look-regression`. It exports the same input with Tri-X, Portra and
Vision3 500T without writing to Photos. Run `python3
ios/Silverphase/Tools/check-video-look.py <Documents directory>` to compare RGB
pixels against the source and across film stocks, not just the track metadata.

The production export memory guard remains active. This check does not test
camera recording, hardware thermals, sustained AV cadence, or playback sync.

## Required acceptance

1. Open the entry from the Library menu, grant camera and microphone
   permissions. Repeat with microphone denied; verify no pretend-silent take,
   and the settings message. Check the original camera and Portrait can still
   open from their normal entry points after leaving video.
2. Check Automatic Maximum and manual controls with each available rear lens.
   Try the highest automatic pair and a lower manual pair; switch to a lens
   without that pair and check the prompt. Controls must be locked during
   recording. Check that high-speed takes play in real time with sound.
   Record in landscape for at least two minutes, including speech or a clap
   near both ends and moving subjects. Stop explicitly. Confirm playback has
   sound and the shot has no ten-second cap. Repeat in portrait with another
   film. Check both orientations at 30 fps and, where offered, repeat at 60 fps.
   Compare each source and output's actual size, average frame rate and orientation.
   Check for repeated frames in a steadily moving subject; metadata alone cannot
   detect cadence/duplication. Run a five-minute recording before release.
3. Develop and save. Verify Photos has one complete video with synced audio,
   visible stock color, grain and halation; do not use only reported metadata.
   Record render wall time, device, OS, peak memory and thermal/fps behavior.
   UHD quadruples frame pixels vs 1080p, and 60 fps doubles rendered frames vs 30.
   The first renderer uses 256-row bands and a conservative still-export-derived
   memory gate; that gate is not a benchmark. If it refuses export, capture may
   still succeed and the original remains available. Do not call that device
   end-to-end capable or silently scale it to a smaller raster.
   Repeat a static scene in shadow to check for artificial temporal flicker.
4. Cancel development; retry. Deny Photos writes; ensure the original still
   plays and is offered on reopening the video screen, then save after granting
   permission. Take a longer recording and background/lock the app: validate
   salvage of finalized footage before calling interruption support verified.
   Verify footage is not silently lost if the disk-space reserve is reached.
5. Run the optional ffprobe comparison on source and developed files (e.g.
   launch Debug with `--video-check-keep-files` to retain both in the app container after saving to Photos; remove the argument after testing):
   `python3 ios/Silverphase/Tools/check-video-pair.py original.mov developed.mov --min-seconds 120 --require-uhd-fps 30`.
   For the five-minute warm run at 60 fps, use `--min-seconds 300 --require-uhd-fps 60`.
   With `--require-uhd-fps`, this decodes the video frames from both files to check
   presentation timestamps across the entire take; UHD may take a while.
   It flags gaps above 25 ms at 60 fps or 50 ms at 30 fps and reports whether
   they occur in the original, developed output, or both. A repeated image can
   still have a regular timestamp, so keep the steady-motion and audio checks.
