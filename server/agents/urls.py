from django.urls import path

from agents import views

urlpatterns = [
    path("agent/sessions/", views.agent_sessions_view, name="agent-sessions"),
    path("agent/models/", views.agent_models_view, name="agent-models"),
    path("agent/messages/", views.agent_messages_view, name="agent-messages"),
    path("agent/stop/", views.agent_stop_view, name="agent-stop"),
    path("agent/status/", views.agent_status_view, name="agent-status"),
]
