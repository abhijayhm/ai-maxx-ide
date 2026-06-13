from django.urls import path

from agents.consumers import AgentConsumer
from remote.consumers import RemoteConsumer
from terminals.consumers import TerminalConsumer

websocket_urlpatterns = [
    path("ws/agent/", AgentConsumer.as_asgi()),
    path("ws/terminals/<int:session_id>/", TerminalConsumer.as_asgi()),
    path("ws/remote/", RemoteConsumer.as_asgi()),
]
