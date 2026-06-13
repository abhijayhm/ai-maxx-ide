"""Screen capture track — stub when aiortc unavailable."""

try:
    from aiortc.contrib.media import MediaRelay
    from aiortc.mediastreams import VideoStreamTrack

    AIORTC_AVAILABLE = True
except ImportError:
    AIORTC_AVAILABLE = False
    MediaRelay = None
    VideoStreamTrack = object


class StubScreenTrack:
    """Placeholder when aiortc is not installed."""

    kind = "video"

    async def recv(self):
        import asyncio

        await asyncio.sleep(0.033)
        return None


if AIORTC_AVAILABLE:

    import asyncio
    import threading

    import numpy as np

    class ScreenTrack(VideoStreamTrack):
        """mss capture thread → queue(maxsize=1) → recv() → VideoFrame"""

        def __init__(self):
            super().__init__()
            self._queue: asyncio.Queue = asyncio.Queue(maxsize=1)
            self._thread = threading.Thread(target=self._capture_loop, daemon=True)
            self._running = True
            self._thread.start()

        def _capture_loop(self):
            try:
                import av
                import mss
            except ImportError:
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
                    except asyncio.QueueFull:
                        pass

        async def recv(self):
            from av import VideoFrame

            frame = await self._queue.get()
            video_frame = VideoFrame.from_ndarray(frame, format="rgb24")
            video_frame.pts, video_frame.time_base = await self.next_timestamp()
            return video_frame

        def stop(self):
            self._running = False

else:
    ScreenTrack = StubScreenTrack

    def get_media_relay():
        return None

if AIORTC_AVAILABLE:
    _relay = MediaRelay()

    def get_media_relay():
        return _relay

    def create_screen_track():
        return ScreenTrack()

else:

    def create_screen_track():
        return StubScreenTrack()
