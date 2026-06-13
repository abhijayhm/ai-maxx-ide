"""WebRTC peer connection for remote desktop streaming."""

from __future__ import annotations

import logging
from typing import Any, Callable, Coroutine

from django.conf import settings

from remote.screen import AIORTC_AVAILABLE, create_screen_track

logger = logging.getLogger(__name__)

SendJson = Callable[[dict], Coroutine[Any, Any, None]]


def webrtc_enabled() -> bool:
    return AIORTC_AVAILABLE and not getattr(settings, "REMOTE_WEBRTC_STUB", False)


async def handle_offer(send_json: SendJson, sdp: str) -> tuple[Any | None, Any | None]:
    """Create peer connection, attach screen track, return (pc, screen_track)."""
    if not webrtc_enabled():
        await send_json({"type": "answer", "sdp": sdp, "stub": True})
        await send_json({"type": "connected"})
        return None, None

    from aiortc import RTCPeerConnection, RTCSessionDescription
    from aiortc.sdp import candidate_to_sdp

    pc = RTCPeerConnection()
    screen_track = create_screen_track()
    pc.addTrack(screen_track)

    @pc.on("icecandidate")
    async def on_icecandidate(event) -> None:
        if event.candidate is None:
            return
        await send_json(
            {
                "type": "ice_candidate",
                "candidate": {
                    "candidate": candidate_to_sdp(event.candidate),
                    "sdpMid": event.candidate.sdpMid,
                    "sdpMLineIndex": event.candidate.sdpMLineIndex,
                },
            }
        )

    offer = RTCSessionDescription(sdp=sdp, type="offer")
    await pc.setRemoteDescription(offer)
    answer = await pc.createAnswer()
    await pc.setLocalDescription(answer)

    await send_json({"type": "answer", "sdp": pc.localDescription.sdp})
    await send_json({"type": "connected"})
    return pc, screen_track


async def add_ice_candidate(pc, payload: dict) -> None:
    if pc is None or not payload:
        return

    from aiortc.sdp import candidate_from_sdp

    candidate = payload.get("candidate") if isinstance(payload, dict) else None
    if not candidate:
        return

    sdp = candidate.get("candidate", "")
    if not sdp:
        return

    ice = candidate_from_sdp(sdp)
    ice.sdpMid = candidate.get("sdpMid")
    ice.sdpMLineIndex = candidate.get("sdpMLineIndex")
    await pc.addIceCandidate(ice)


async def close_peer(pc, screen_track) -> None:
    if screen_track is not None and hasattr(screen_track, "stop"):
        screen_track.stop()
    if pc is not None:
        await pc.close()
