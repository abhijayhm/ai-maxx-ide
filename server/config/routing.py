from django.urls import path

from agents.consumers import AgentConsumer
from ide.consumers import GetByPathConsumer, GitConsumer, IdeSearchConsumer, WatchdogConsumer

websocket_urlpatterns = [
    path("api/ws/watchdog/", WatchdogConsumer.as_asgi()),
    path("api/ws/ide_search/", IdeSearchConsumer.as_asgi()),
    path("api/ws/getbypath/", GetByPathConsumer.as_asgi()),
    path("api/ws/git/", GitConsumer.as_asgi()),
    path("api/ws/agent/", AgentConsumer.as_asgi()),
]
