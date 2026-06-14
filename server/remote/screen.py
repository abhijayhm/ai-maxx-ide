"""Screen capture track via mss + aiortc."""

from __future__ import annotations

import asyncio
import logging
import queue
import threading

logger = logging.getLogger(__name__)

try:
    from aiortc.contrib.media import MediaRelay
    from aiortc.mediastreams import VideoStreamTrack

    AIORTC_AVAILABLE = True
except ImportError:
    AIORTC_AVAILABLE = False
    MediaRelay = None  # type: ignore[misc, assignment]
    VideoStreamTrack = object  # type: ignore[misc, assignment]


class StubScreenTrack:
    """Placeholder when aiortc is not installed."""

    kind = "video"

    async def recv(self):
        await asyncio.sleep(0.033)
        return None

    def stop(self) -> None:
        pass


if AIORTC_AVAILABLE:

    import numpy as np

    def _bgra_to_rgb(raw: np.ndarray) -> np.ndarray:
        return raw[:, :, [2, 1, 0]]

    def _overlay_system_cursor(frame: np.ndarray, monitor: dict) -> np.ndarray:
        """Burn a high-contrast cursor marker into frames (mss excludes HW cursor)."""
        from remote.cursor import read_cursor_position

        abs_x, abs_y = read_cursor_position()
        cx = int(abs_x - monitor["left"])
        cy = int(abs_y - monitor["top"])
        h, w = frame.shape[:2]
        if cx < 0 or cy < 0 or cx >= w or cy >= h:
            return frame

        out = frame.copy()
        radius = 12
        y0, y1 = max(0, cy - radius - 3), min(h, cy + radius + 4)
        x0, x1 = max(0, cx - radius - 3), min(w, cx + radius + 4)
        patch_y, patch_x = np.ogrid[y0:y1, x0:x1]
        dist_sq = (patch_x - cx) ** 2 + (patch_y - cy) ** 2
        inner = dist_sq <= radius**2
        ring = (dist_sq <= (radius + 2) ** 2) & ~inner
        patch = out[y0:y1, x0:x1]
        patch[inner] = (255, 220, 0)
        patch[ring] = (0, 0, 0)

        for x in range(max(0, cx - 16), min(w, cx + 17)):
            out[cy, x] = (255, 64, 64)
        for y in range(max(0, cy - 16), min(h, cy + 17)):
            out[y, cx] = (255, 64, 64)

        return out

    class ScreenTrack(VideoStreamTrack):
        """mss capture thread → queue(maxsize=1) → recv() → VideoFrame."""

        kind = "video"

        def __init__(self):
            super().__init__()
            self._queue: queue.Queue = queue.Queue(maxsize=1)
            self._running = True
            self._monitor: dict = {}
            self._thread = threading.Thread(target=self._capture_loop, daemon=True)
            self._thread.start()

        def _capture_loop(self) -> None:
            try:
                import mss
            except ImportError:
                logger.warning("mss not installed — screen capture disabled")
                return

            with mss.mss() as sct:
                self._monitor = dict(sct.monitors[1])
                while self._running:
                    img = sct.grab(self._monitor)
                    frame = _bgra_to_rgb(np.array(img))
                    h, w = frame.shape[:2]
                    w8 = w - (w % 8)
                    h8 = h - (h % 8)
                    frame = frame[:h8, :w8]
                    try:
                        self._queue.put_nowait(frame)
                    except queue.Full:
                        try:
                            self._queue.get_nowait()
                        except queue.Empty:
                            pass
                        try:
                            self._queue.put_nowait(frame)
                        except queue.Full:
                            pass

        async def recv(self):
            from av import VideoFrame

            loop = asyncio.get_running_loop()
            frame = await loop.run_in_executor(None, self._queue.get)
            if self._monitor:
                frame = _overlay_system_cursor(frame, self._monitor)
            video_frame = VideoFrame.from_ndarray(frame, format="rgb24")
            video_frame.pts, video_frame.time_base = await self.next_timestamp()
            return video_frame

        def stop(self) -> None:
            self._running = False

    _relay = MediaRelay()

    def get_media_relay():
        return _relay

    def create_screen_track():
        return ScreenTrack()

else:
    ScreenTrack = StubScreenTrack  # type: ignore[misc, assignment]

    def get_media_relay():
        return None

    def create_screen_track():
        return StubScreenTrack()
