# Video device check

This draft exposes a separate UHD (3840 × 2160) SDR HEVC rear-camera recorder in Library → ⋯ →
Record Video in Debug only, until device acceptance. It has no application recording-duration cap. Recording stays in
the foreground, with sound; interruptions end the current take rather than
trying to resume into the same file. Capture quality, thermal behavior, and
export speed are not yet validated on iPhone.

The hardware writes a QuickTime source; the separate post-capture pass uses the
selected film's normal print/scan workflow through the native Metal engine,
one frame at a time. It preserves the audio track and has no app-imposed limit
on the source length. 30 fps is the default; 60 fps is only offered if the rear camera reports a compatible UHD SDR format. Capture and export validate the actual raster, nominal frame rate, and HEVC codec. No automatic downgrade. The live viewfinder is ungraded. Glare and per-frame film
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

## Required acceptance

1. Open the entry from the Library menu, grant camera and microphone
   permissions. Repeat with microphone denied; verify no pretend-silent take,
   and the settings message. Check the original camera and Portrait can still
   open from their normal entry points after leaving video.
2. Record in landscape for at least two minutes, including speech or a clap
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
   Repeat with `--require-uhd-fps 60` on the 60 fps take.
   This checks displayed dimensions, track timing/duration, audio presence and
   SDR tags; visual and audio inspection still matter.
