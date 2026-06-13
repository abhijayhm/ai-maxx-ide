from django.urls import path

from agents.consumers import AgentConsumer
from files.consumers import WorkspaceSyncConsumer
from remote.consumers import RemoteConsumer
from terminals.consumers import TerminalConsumer

websocket_urlpatterns = [
    path("api/ws/agent/", AgentConsumer.as_asgi()),
    path("api/ws/sync/<int:workspace_id>/", WorkspaceSyncConsumer.as_asgi()),
    path("api/ws/terminals/<int:session_id>/", TerminalConsumer.as_asgi()),
    path("api/ws/remote/", RemoteConsumer.as_asgi()),
]
