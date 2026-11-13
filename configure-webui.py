#!/usr/bin/env python3
import base64
import configparser
import hashlib
import os
from pathlib import Path
import secrets
import sys
import tempfile


def configure(config_path):
    username = os.environ.get("WEBUI_USERNAME")
    password = os.environ.get("WEBUI_PASSWORD")
    password_file = os.environ.get("WEBUI_PASSWORD_FILE")
    legacy_password = os.environ.get("WEB_PASSWORD")
    legacy_file = os.environ.get("WEB_PASSWORD_FILE")
    passwords = [value for value in (password, password_file, legacy_password, legacy_file) if value is not None]
    if len(passwords) > 1:
        raise ValueError("Set only one of WEBUI_PASSWORD, WEBUI_PASSWORD_FILE, WEB_PASSWORD or WEB_PASSWORD_FILE")
    if password is None:
        password = legacy_password
    password_file = password_file if password_file is not None else legacy_file
    if password_file is not None:
        password = Path(password_file).read_text(encoding="utf-8").rstrip("\r\n")
    if username is None and password is None:
        return
    if username is not None and (not username or any(character in username for character in "\r\n\0")):
        raise ValueError("WEBUI_USERNAME must be non-empty and contain no line breaks or NUL")
    if password is not None and not password:
        raise ValueError("WebUI password must not be empty")

    config = configparser.RawConfigParser(strict=False)
    config.optionxform = str
    with config_path.open(encoding="utf-8") as source:
        config.read_file(source)
    if not config.has_section("Preferences"):
        config.add_section("Preferences")
    if username is not None:
        escaped_username = username.replace("\\", "\\\\").replace('"', '\\"')
        if escaped_username.startswith("@"):
            escaped_username = "@" + escaped_username
        config.set("Preferences", "WebUI\\Username", f'"{escaped_username}"')
    if password is not None:
        salt = secrets.token_bytes(16)
        digest = hashlib.pbkdf2_hmac("sha512", password.encode("utf-8"), salt, 100000)
        encoded = base64.b64encode(salt).decode() + ":" + base64.b64encode(digest).decode()
        config.set("Preferences", "WebUI\\Password_PBKDF2", f'"@ByteArray({encoded})"')
        config.remove_option("Preferences", "WebUI\\Password_ha1")

    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=config_path.parent, delete=False) as output:
            temporary_path = Path(output.name)
            config.write(output, space_around_delimiters=False)
        temporary_path.replace(config_path)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        configure(Path(sys.argv[1]))
    except (OSError, ValueError, configparser.Error):
        sys.exit("Cannot configure WebUI credentials; check variables, password file and config directory permissions")
