#!/usr/bin/env python3
"""A storyboard of Nine on the Vision Pro simulator: one screenshot per step,
assembled into a video.

`nine/docs/vision/SHOTLIST.md` was made by hand with the commands below, and
this is those commands kept. Why a storyboard and not a recording is written
there: the visionOS simulator vends no HID digitizer, so nothing can be pinched
from a script, and `simctl io recordVideo` starved the simulator to one frame
every ten seconds. So the app stages itself (`--vision-tour`, DEBUG only), one
step per `vision-go` file (`--vision-wait-go`), and this photographs each step
once the simulator has actually drawn it.

    python3 nine/scripts/vision-storyboard.py                    # build, tour, video
    python3 nine/scripts/vision-storyboard.py --no-build --args --vision-solve
    python3 nine/scripts/vision-storyboard.py --out /tmp/board --burst 12

What it does, in order:

  1. boots the "Nine Vision" simulator (`simrig.prepare_vision_simulator`) and
     installs a DEBUG `NineVision` (`simrig.build_and_install`);
  2. photographs the empty room, launches Nine with the staging arguments, and
     **waits for the first frame by luminance**: the board's glass slab moves
     the mean luminance of the frame off the empty room's, and two polls that
     agree say it has settled. A launch on a loaded host took minutes inside
     RealityKit's scene setup, so a fixed sleep is either too long or wrong;
  3. **steps with `vision-go`**: drops the file into the app's tmp directory,
     waits for the app to consume it (it deletes it), waits for the frame to
     settle, photographs. A file that is not consumed within `--step-timeout`
     means the tour has no more pauses: the run is over;
  4. **bursts after the solving step** — `--burst` frames back to back, right
     after step `--burst-after` is consumed (17 for `--vision-tour`, whose 17th
     `vision-go` releases the last digit; 1 otherwise), because the solve's
     Afterglow and sparks last about a second and the lift holds;
  5. **assembles** the frames with ffmpeg into `storyboard.mp4`, each step held
     `--hold` seconds and each burst frame `--burst-hold`.

`--measure-launch N` instead times N cold launches to the first frame with the
same luminance test (no staging, no video) — the launch-performance probe.

Luminance is measured by ffmpeg (scale to one grey pixel), so the only
dependency is the ffmpeg the video needs anyway.
"""

import argparse
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import simrig  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # nine/


def screenshot(udid, path):
    simrig.run(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", path])
    return path


def luminance(path):
    """Mean luminance 0–255 of an image, by ffmpeg: scale to 1×1 grey."""
    out = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-vf", "scale=1:1:flags=area,format=gray",
         "-f", "rawvideo", "-"],
        check=True, capture_output=True).stdout
    return float(out[0]) if out else 0.0


def container_tmp(udid):
    data = simrig.run(["xcrun", "simctl", "get_app_container", udid,
                       simrig.VISION_BUNDLE_ID, "data"]).strip()
    return os.path.join(data, "tmp")


def wait_for_first_frame(udid, room, scratch, delta, timeout, poll):
    """Until the frame differs from the empty room by `delta` and two polls
    agree within a quarter of it."""
    base = luminance(room)
    deadline = time.time() + timeout
    last = None
    n = 0
    while time.time() < deadline:
        time.sleep(poll)
        n += 1
        level = luminance(screenshot(udid, os.path.join(scratch, "probe-%03d.png" % n)))
        moved = abs(level - base) >= delta
        print("  first frame? luminance %.1f (room %.1f)%s"
              % (level, base, " — moved" if moved else ""))
        if moved and last is not None and abs(level - last) <= delta / 4:
            return
        last = level if moved else None
    sys.exit("no first frame in %ds — the board never drew (RealityKit scene "
             "setup can take minutes on a loaded host; raise --first-frame-timeout)"
             % int(timeout))


def settle(udid, scratch, tag, tolerance, poll, limit=8):
    """Photograph until two frames agree, and keep the last."""
    previous = None
    for n in range(limit):
        path = screenshot(udid, os.path.join(scratch, "%s-try%d.png" % (tag, n)))
        level = luminance(path)
        if previous is not None and abs(level - previous) <= tolerance:
            return path
        previous = level
        time.sleep(poll)
    return path


def step(udid, tmp, timeout):
    """Drop `vision-go`; True once the app has consumed it."""
    go = os.path.join(tmp, "vision-go")
    os.makedirs(tmp, exist_ok=True)
    open(go, "w").close()
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not os.path.exists(go):
            return True
        time.sleep(0.25)
    os.remove(go)
    return False


def assemble(frames, out, hold, burst_hold, size):
    """ffmpeg's concat demuxer, one line per frame with its own duration."""
    listing = os.path.join(os.path.dirname(out), "frames.txt")
    with open(listing, "w") as handle:
        for path, seconds in frames:
            handle.write("file '%s'\nduration %.3f\n" % (path, seconds))
        # The concat demuxer drops the last duration without a trailing entry.
        handle.write("file '%s'\n" % frames[-1][0])
    w, h = size
    simrig.run([
        "ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing,
        "-vf", "scale=%d:%d:force_original_aspect_ratio=decrease,"
               "pad=%d:%d:(ow-iw)/2:(oh-ih)/2,format=yuv420p" % (w, h, w, h),
        "-r", "30", "-c:v", "libx264", "-crf", "20", out])


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--simulator", default="Nine Vision")
    parser.add_argument("--no-build", action="store_true",
                        help="install the app already in build/ (or --app)")
    parser.add_argument("--app", help="a built NineVision.app to install instead of building")
    parser.add_argument("--args", nargs=argparse.REMAINDER,
                        default=["--vision-tour"],
                        help="staging launch arguments (default: --vision-tour); "
                             "--vision-wait-go is always added")
    parser.add_argument("--out", default=os.path.join(REPO, "build", "vision-storyboard"))
    parser.add_argument("--hold", type=float, default=2.5, help="seconds per step")
    parser.add_argument("--burst", type=int, default=8, help="frames after the last step")
    parser.add_argument("--burst-hold", type=float, default=0.4)
    parser.add_argument("--burst-after", type=int,
                        help="the step whose go releases the solve "
                             "(default 17 for --vision-tour, else 1)")
    parser.add_argument("--delta", type=float, default=2.0,
                        help="luminance change (0–255) that means the board drew")
    parser.add_argument("--first-frame-timeout", type=float, default=900)
    parser.add_argument("--step-timeout", type=float, default=20)
    parser.add_argument("--poll", type=float, default=3.0)
    parser.add_argument("--size", default="1920x1080")
    parser.add_argument("--measure-launch", type=int, metavar="N",
                        help="time N cold launches to first frame, then stop")
    opts = parser.parse_args()

    os.makedirs(opts.out, exist_ok=True)
    scratch = os.path.join(opts.out, "probes")
    os.makedirs(scratch, exist_ok=True)
    udid = simrig.prepare_vision_simulator(opts.simulator)
    print("simulator %s (%s)" % (opts.simulator, udid))

    app = opts.app
    if opts.no_build and app is None:
        app = os.path.join(REPO, "build", "Build", "Products", "Debug-xrsimulator", "NineVision.app")
    simrig.run(["xcrun", "simctl", "terminate", udid, simrig.VISION_BUNDLE_ID], check=False)
    simrig.build_and_install(udid, app, REPO, scheme="NineVision", products="Debug-xrsimulator",
                            bundle="NineVision.app")

    if opts.measure_launch:
        times = []
        for i in range(opts.measure_launch):
            simrig.run(["xcrun", "simctl", "terminate", udid, simrig.VISION_BUNDLE_ID],
                       check=False)
            time.sleep(opts.poll)
            room = screenshot(udid, os.path.join(scratch, "room-%d.png" % i))
            start = time.time()
            simrig.run(["xcrun", "simctl", "launch", udid, simrig.VISION_BUNDLE_ID])
            wait_for_first_frame(udid, room, scratch, opts.delta,
                                 opts.first_frame_timeout, min(opts.poll, 1.0))
            times.append(time.time() - start)
            print("launch %d: %.1f s to first frame" % (i + 1, times[-1]))
        times.sort()
        print("first frame: min %.1f s, median %.1f s, max %.1f s over %d launches "
              "(resolution: one screenshot, ~%.0f s)"
              % (times[0], times[len(times) // 2], times[-1], len(times), min(opts.poll, 1.0)))
        return

    room = screenshot(udid, os.path.join(scratch, "room.png"))
    args = list(opts.args) + ["--vision-wait-go"]
    print("launching with %s" % " ".join(args))
    simrig.run(["xcrun", "simctl", "launch", udid, simrig.VISION_BUNDLE_ID] + args)
    wait_for_first_frame(udid, room, scratch, opts.delta, opts.first_frame_timeout, opts.poll)

    burst_after = opts.burst_after or (17 if "--vision-tour" in args else 1)
    tmp = container_tmp(udid)
    frames = [(settle(udid, opts.out, "shot-000", opts.delta / 4, opts.poll), opts.hold)]
    n = 0
    while True:
        n += 1
        if not step(udid, tmp, opts.step_timeout):
            print("step %d not consumed in %ds: the run is over" % (n, int(opts.step_timeout)))
            break
        if n == burst_after:
            # No settling: the Afterglow and the sparks are over in a second.
            for b in range(opts.burst):
                frames.append((screenshot(udid, os.path.join(opts.out, "burst-%02d.png" % b)),
                               opts.burst_hold))
            print("step %d: burst of %d" % (n, opts.burst))
            continue
        frames.append((settle(udid, opts.out, "shot-%03d" % n, opts.delta / 4, opts.poll),
                       opts.hold))
        print("step %d photographed" % n)

    w, h = (int(x) for x in opts.size.split("x"))
    video = os.path.join(opts.out, "storyboard.mp4")
    assemble(frames, video, opts.hold, opts.burst_hold, (w, h))
    print("wrote %s (%d frames)" % (video, len(frames)))


if __name__ == "__main__":
    main()
