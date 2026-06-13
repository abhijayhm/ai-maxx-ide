from django.urls import path

from gitapp import views

urlpatterns = [
    path("git/status/", views.git_status_view, name="git-status"),
    path("git/stage/", views.git_stage_view, name="git-stage"),
    path("git/unstage/", views.git_unstage_view, name="git-unstage"),
    path("git/discard/", views.git_discard_view, name="git-discard"),
    path("git/stash/", views.git_stash_view, name="git-stash"),
    path("git/commit/", views.git_commit_view, name="git-commit"),
    path("git/sync/", views.git_sync_view, name="git-sync"),
    path("git/exec/", views.git_exec_view, name="git-exec"),
    path("git/branches/", views.git_branches_view, name="git-branches"),
    path("git/checkout/", views.git_checkout_view, name="git-checkout"),
    path("git/log/", views.git_log_view, name="git-log"),
]
