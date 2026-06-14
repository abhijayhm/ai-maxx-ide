from django.urls import path

from terminals import views

urlpatterns = [
    path("terminals/", views.terminal_list_create_view, name="terminal-list"),
    path("terminals/<int:terminal_id>/", views.terminal_detail_view, name="terminal-detail"),
    path("terminals/<int:terminal_id>/exec/", views.terminal_exec_view, name="terminal-exec"),
    path("terminals/<int:terminal_id>/io/", views.terminal_io_view, name="terminal-io"),
]
