from django.urls import path

from dashboard import views

urlpatterns = [
    path("scripts/", views.dashboard_scripts_view, name="dashboard-scripts"),
    path("run/", views.dashboard_run_view, name="dashboard-run"),
    path("jobs/<str:script_id>/", views.dashboard_job_view, name="dashboard-job"),
]
