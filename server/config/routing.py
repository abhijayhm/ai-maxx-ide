from django.urls import path

from ide.consumers import GitConsumer, IdeSearchConsumer, WatchdogConsumer

websocket_urlpatterns = [
    path("api/ws/watchdog/", WatchdogConsumer.as_asgi()),
    path("api/ws/ide_search/", IdeSearchConsumer.as_asgi()),
    path("api/ws/git/", GitConsumer.as_asgi()),
]
