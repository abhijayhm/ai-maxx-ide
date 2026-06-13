from django.urls import path

from files import views

urlpatterns = [
    path("", views.workspace_sync_view, name="workspace-sync"),
    path("files/", views.workspace_sync_files_view, name="workspace-sync-files"),
]
