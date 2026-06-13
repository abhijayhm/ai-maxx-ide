import pytest

from core.utils.paths import PathNotAllowedError, is_under_exposed_roots, resolve_allowed_path


def test_resolve_allowed_path_under_root(exposed_root, settings):
    child = exposed_root / "project"
    child.mkdir()
    resolved = resolve_allowed_path(str(child))
    assert resolved == child.resolve()


def test_resolve_rejects_outside_root(tmp_path, settings):
    outside = tmp_path / "outside"
    outside.mkdir()
    exposed_root = tmp_path / "root"
    exposed_root.mkdir()
    settings.EXPOSED_DIRECTORIES_ABSOLUTE_PATHS = [str(exposed_root)]
    with pytest.raises(PathNotAllowedError):
        resolve_allowed_path(str(outside))


def test_resolve_rejects_traversal(exposed_root):
    with pytest.raises(PathNotAllowedError):
        resolve_allowed_path(str(exposed_root / ".." / ".." / "etc" / "passwd"))


def test_is_under_exposed_roots(exposed_root, settings):
    sub = exposed_root / "a" / "b"
    sub.mkdir(parents=True)
    assert is_under_exposed_roots(sub)
    assert not is_under_exposed_roots(exposed_root.parent.parent)
