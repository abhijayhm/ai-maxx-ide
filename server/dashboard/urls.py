from django.urls import path

from dashboard import views

urlpatterns = [
    path("", views.dashboard_page, name="dashboard"),
    path("run/", views.dashboard_run_form, name="dashboard-run-form"),
]

api_urlpatterns = []
