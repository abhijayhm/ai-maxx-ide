from rest_framework import serializers

from core.models import AgentMessage, DeviceIdentifier, Workspace


class DeviceRegisterSerializer(serializers.Serializer):
    hash = serializers.CharField(max_length=64)
    data = serializers.JSONField()


class DeviceIdentifierSerializer(serializers.Serializer):
    data = serializers.JSONField()


class WorkspaceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Workspace
        fields = [
            "id",
            "absolute_path",
            "label",
            "cursor_agent_id",
            "is_active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "cursor_agent_id", "created_at", "updated_at"]


class WorkspaceCreateSerializer(serializers.Serializer):
    absolute_path = serializers.CharField()


class WorkspacePatchSerializer(serializers.Serializer):
    label = serializers.CharField(max_length=255, required=False, allow_blank=True)
    is_active = serializers.BooleanField(required=False)


class AgentMessageSerializer(serializers.ModelSerializer):
    class Meta:
        model = AgentMessage
        fields = [
            "id",
            "timestamp",
            "sender",
            "receiver",
            "run_id",
            "payload",
        ]
