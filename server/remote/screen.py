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

    class ScreenTrack(VideoStreamTrack):
        """mss capture thread → queue(maxsize=1) → recv() → VideoFrame."""

        kind = "video"

        def __init__(self):
            super().__init__()
            self._queue: queue.Queue = queue.Queue(maxsize=1)
            self._running = True
            self._thread = threading.Thread(target=self._capture_loop, daemon=True)
            self._thread.start()

        def _capture_loop(self) -> None:
            try:
                import mss
            except ImportError:
                logger.warning("mss not installed — screen capture disabled")
                return

            with mss.mss() as sct:
                monitor = sct.monitors[1]
                while self._running:
                    img = sct.grab(monitor)
                    frame = np.array(img)[:, :, :3]
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
