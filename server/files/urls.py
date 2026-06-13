from django.urls import path

from files import views

urlpatterns = [
    path("files/roots/", views.files_roots_view, name="files-roots"),
    path("files/by-path/", views.files_by_path_view, name="files-by-path"),
    path("files/download/", views.files_download_view, name="files-download"),
    path("files/mkdir/", views.files_mkdir_view, name="files-mkdir"),
    path("files/touch/", views.files_touch_view, name="files-touch"),
    path("search/files/", views.search_files_view, name="search-files"),
    path("search/grep/", views.search_grep_view, name="search-grep"),
]
