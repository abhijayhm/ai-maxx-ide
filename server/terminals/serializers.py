from rest_framework import serializers

from terminals.models import TerminalIO


class TerminalIOSerializer(serializers.ModelSerializer):
    class Meta:
        model = TerminalIO
        fields = ["id", "direction", "data", "created_at"]
        read_only_fields = fields
