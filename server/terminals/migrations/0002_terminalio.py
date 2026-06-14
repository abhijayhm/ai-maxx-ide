import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("terminals", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="TerminalIO",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                (
                    "direction",
                    models.CharField(
                        choices=[("input", "Input"), ("output", "Output")],
                        max_length=8,
                    ),
                ),
                ("data", models.TextField()),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "terminal",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="io_lines",
                        to="terminals.terminal",
                    ),
                ),
            ],
            options={
                "ordering": ["created_at"],
                "indexes": [
                    models.Index(
                        fields=["terminal", "created_at"],
                        name="terminals_t_termina_6f0f0d_idx",
                    )
                ],
            },
        ),
    ]
