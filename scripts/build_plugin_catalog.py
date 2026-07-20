#!/usr/bin/env python3
"""Discover public SideCord plugins and publish a signed, deterministic catalog."""

from __future__ import annotations

import argparse
import base64
import hashlib
import ipaddress
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


IDENTIFIER = re.compile(r"^[a-z0-9]+(?:[.-][a-z0-9]+)+$")
VERSION = re.compile(r"^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$")
CATEGORY = re.compile(r"^[a-z0-9][a-z0-9-]{0,39}$")
HOST_LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
SELECTOR = re.compile(r"^[A-Za-z0-9_.#\[\]='\" -]+(?: > [A-Za-z0-9_.#\[\]='\" -]+)*$")
CAPABILITY_CONTRIBUTIONS = {
    "theme": "themes",
    "layout": "layouts",
    "styleSheet": "styleSheets",
    "command": "commands",
    "webPanel": "webPanels",
}
SPECIAL_PERMISSIONS = {"persistentWebsiteData", "backgroundAudio"}
FORBIDDEN_KEYS = {"javascript", "script", "nativeLibrary", "executable", "shellCommand"}
MAX_PACKAGE_SIZE = 1_000_000
MAX_CATALOG_REPOSITORIES = 400


class RejectedPlugin(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RejectedPlugin(message)


def api_json(path: str, token: str) -> dict[str, Any]:
    request = urllib.request.Request(
        f"https://api.github.com{path}",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "SideCord-Catalog-Builder",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def download(url: str, token: str, maximum_size: int = MAX_PACKAGE_SIZE) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {token}", "User-Agent": "SideCord-Catalog-Builder"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        content_length = int(response.headers.get("Content-Length", "0") or 0)
        require(content_length <= maximum_size, "package exceeds the size limit")
        data = response.read(maximum_size + 1)
    require(len(data) <= maximum_size, "package exceeds the size limit")
    return data


def discover_repositories(token: str) -> list[dict[str, Any]]:
    repositories: list[dict[str, Any]] = []
    for page in range(1, 5):
        query = urllib.parse.quote("topic:sidecord-plugin is:public")
        result = api_json(f"/search/repositories?q={query}&sort=updated&per_page=100&page={page}", token)
        items = result.get("items", [])
        require(isinstance(items, list), "GitHub search returned malformed data")
        repositories.extend(items)
        if len(items) < 100 or len(repositories) >= MAX_CATALOG_REPOSITORIES:
            break
    return repositories[:MAX_CATALOG_REPOSITORIES]


def repository_file(repository: str, path: str, token: str) -> bytes:
    encoded_path = urllib.parse.quote(path, safe="/")
    result = api_json(f"/repos/{repository}/contents/{encoded_path}", token)
    require(result.get("type") == "file", f"{path} is not a file")
    require(result.get("encoding") == "base64", f"{path} has an unsupported encoding")
    try:
        return base64.b64decode(result["content"], validate=True)
    except (KeyError, ValueError) as error:
        raise RejectedPlugin(f"{path} is not valid Base64 content") from error


def exact_host(value: Any) -> str:
    require(isinstance(value, str) and value == value.lower(), "hosts must be lowercase strings")
    require(1 < len(value) <= 253 and not value.startswith(".") and not value.endswith("."), "invalid host")
    require("*" not in value, "wildcard hosts are forbidden")
    try:
        ipaddress.ip_address(value)
    except ValueError:
        pass
    else:
        raise RejectedPlugin("IP-address hosts are forbidden")
    labels = value.split(".")
    require(len(labels) >= 2 and all(HOST_LABEL.fullmatch(label) for label in labels), "invalid exact host")
    return value


def safe_https_url(value: Any) -> urllib.parse.ParseResult:
    require(isinstance(value, str), "URL must be a string")
    parsed = urllib.parse.urlparse(value)
    require(parsed.scheme == "https" and parsed.hostname, "URL must use HTTPS")
    require(parsed.username is None and parsed.password is None and parsed.port is None, "URL credentials and ports are forbidden")
    exact_host(parsed.hostname)
    return parsed


def validate_css(css: Any) -> None:
    require(isinstance(css, str) and len(css.encode()) <= 65_536, "invalid CSS")
    lowered = css.lower()
    require(not any(token in lowered for token in ("@", "url(", "expression(", "javascript:", "/*", "*/", "\\")), "unsafe CSS")


def validate_selector(value: Any) -> None:
    require(isinstance(value, str) and 0 < len(value) <= 256, "invalid selector")
    require(value == value.strip() and "  " not in value and SELECTOR.fullmatch(value), "unsafe selector")
    require(value.count("[") == value.count("]") and value.count("'") % 2 == 0 and value.count('"') % 2 == 0, "unbalanced selector")


def reject_executable_fields(value: Any) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            require(key not in FORBIDDEN_KEYS, f"forbidden executable field: {key}")
            reject_executable_fields(child)
    elif isinstance(value, list):
        for child in value:
            reject_executable_fields(child)


def validate_package(data: bytes) -> dict[str, Any]:
    require(len(data) <= MAX_PACKAGE_SIZE, "package exceeds the size limit")
    try:
        package = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RejectedPlugin("package is not valid UTF-8 JSON") from error
    require(isinstance(package, dict) and set(package) == {"manifest"}, "package must contain exactly one manifest")
    reject_executable_fields(package)
    manifest = package["manifest"]
    require(isinstance(manifest, dict), "manifest is not an object")
    schema = manifest.get("schemaVersion")
    require(schema in (1, 2, 3), "unsupported plugin schema")
    require(IDENTIFIER.fullmatch(manifest.get("identifier", "")) is not None, "invalid identifier")
    require(VERSION.fullmatch(manifest.get("version", "")) is not None, "invalid version")
    require(VERSION.fullmatch(manifest.get("minimumSideCordVersion", "")) is not None, "invalid minimum SideCord version")
    for key, maximum in (("name", 80), ("author", 80), ("description", 500)):
        require(isinstance(manifest.get(key), str) and 0 < len(manifest[key]) <= maximum, f"invalid {key}")

    capabilities = manifest.get("capabilities")
    require(isinstance(capabilities, list) and len(capabilities) == len(set(capabilities)), "invalid capabilities")
    require(set(capabilities) <= set(CAPABILITY_CONTRIBUTIONS), "unknown capability")
    contributions = manifest.get("contributions")
    require(isinstance(contributions, dict) and set(contributions) <= set(CAPABILITY_CONTRIBUTIONS.values()), "invalid contributions")
    actual = {
        capability for capability, key in CAPABILITY_CONTRIBUTIONS.items()
        if isinstance(contributions.get(key, []), list) and contributions.get(key)
    }
    require(actual == set(capabilities), "capabilities do not exactly match contributions")
    identifiers: list[str] = []
    for entries in contributions.values():
        require(isinstance(entries, list), "contribution group is not a list")
        for entry in entries:
            require(isinstance(entry, dict) and isinstance(entry.get("id"), str), "invalid contribution")
            identifiers.append(entry["id"])
    require(len(identifiers) == len(set(identifiers)), "duplicate contribution identifier")

    for style in contributions.get("styleSheets", []):
        validate_css(style.get("css"))
    permissions = manifest.get("permissions", {})
    require(isinstance(permissions, dict), "permissions are not an object")
    require(set(permissions) <= {"networkHosts", "persistentWebsiteData", "backgroundAudio"}, "unknown permission")
    hosts = permissions.get("networkHosts", [])
    require(isinstance(hosts, list) and len(hosts) <= 16 and len(hosts) == len(set(hosts)), "invalid network hosts")
    hosts = [exact_host(host) for host in hosts]
    for flag in ("persistentWebsiteData", "backgroundAudio"):
        require(isinstance(permissions.get(flag, False), bool), f"invalid {flag} permission")

    panels = contributions.get("webPanels", [])
    require(len(panels) <= 1, "only one web panel is supported")
    require(not panels or schema >= 2, "web panels require schema v2")
    require(panels or not permissions, "web-panel permissions require a web panel")
    for panel in panels:
        initial = safe_https_url(panel.get("initialURL"))
        allowed = panel.get("allowedNavigationHosts")
        require(isinstance(allowed, list) and 0 < len(allowed) <= 16 and len(allowed) == len(set(allowed)), "invalid navigation hosts")
        allowed = [exact_host(host) for host in allowed]
        require(initial.hostname in allowed and set(allowed) <= set(hosts), "navigation hosts exceed permissions")
        require(panel.get("placement") == "bottom", "unsupported panel placement")
        for key in ("preferredHeight", "minimumHeight", "maximumHeight"):
            if key in panel and panel[key] is not None:
                require(isinstance(panel[key], (int, float)) and panel[key] > 0, f"invalid {key}")
        if panel.get("minimumHeight") is not None and panel.get("maximumHeight") is not None:
            require(panel["minimumHeight"] <= panel["maximumHeight"], "panel heights are reversed")
        if panel.get("customCSS") is not None:
            validate_css(panel["customCSS"])
        layouts = panel.get("documentLayouts", [])
        require(not layouts or schema >= 3, "document layouts require schema v3")
        require(isinstance(layouts, list) and len(layouts) <= 16, "invalid document layouts")
        layout_hosts: list[str] = []
        for layout in layouts:
            require(isinstance(layout, dict) and layout.get("host") in allowed, "invalid layout host")
            layout_hosts.append(layout["host"])
            validate_selector(layout.get("mountSelector"))
            slots = layout.get("slots")
            require(isinstance(slots, list) and 0 < len(slots) <= 8, "invalid layout slots")
            slot_ids: list[str] = []
            for slot in slots:
                require(isinstance(slot, dict) and re.fullmatch(r"[a-z][a-z0-9-]{0,39}", slot.get("id", "")), "invalid slot identifier")
                slot_ids.append(slot["id"])
                selectors = slot.get("selectors")
                require(isinstance(selectors, list) and 0 < len(selectors) <= 8 and len(selectors) == len(set(selectors)), "invalid slot selectors")
                for selector in selectors:
                    validate_selector(selector)
                require(slot.get("selection", "first") in ("first", "firstVisible"), "invalid slot selection")
                require(slot.get("strategy", "move") in ("move", "preserve"), "invalid slot strategy")
            require(len(slot_ids) == len(set(slot_ids)), "duplicate slot identifier")
        require(len(layout_hosts) == len(set(layout_hosts)), "duplicate layout host")
    return manifest


def catalog_permissions(manifest: dict[str, Any]) -> list[str]:
    permissions = set(manifest["capabilities"])
    declared = manifest.get("permissions", {})
    for name in SPECIAL_PERMISSIONS:
        if declared.get(name, False):
            permissions.add(name)
    return sorted(permissions)


def validate_metadata(data: bytes) -> dict[str, Any]:
    try:
        metadata = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RejectedPlugin(".sidecord/marketplace.json is invalid") from error
    require(isinstance(metadata, dict), "marketplace metadata is not an object")
    require(set(metadata) <= {"schemaVersion", "package", "icon", "categories", "summary"}, "unknown marketplace metadata field")
    require(metadata.get("schemaVersion") == 1, "unsupported marketplace metadata schema")
    package = metadata.get("package")
    require(isinstance(package, str) and PurePosixPath(package).name == package and package.endswith(".json"), "package must name one release JSON asset")
    summary = metadata.get("summary")
    require(isinstance(summary, str) and 0 < len(summary) <= 280, "invalid marketplace summary")
    categories = metadata.get("categories", [])
    require(isinstance(categories, list) and len(categories) <= 12 and len(categories) == len(set(categories)), "invalid categories")
    require(all(isinstance(item, str) and CATEGORY.fullmatch(item) for item in categories), "invalid category")
    icon = metadata.get("icon")
    if icon is not None:
        path = PurePosixPath(icon)
        require(isinstance(icon, str) and not path.is_absolute() and ".." not in path.parts, "icon must be a safe repository-relative path")
    return metadata


def build_entry(repo: dict[str, Any], token: str, verified: set[str]) -> dict[str, Any]:
    full_name = repo["full_name"]
    metadata = validate_metadata(repository_file(full_name, ".sidecord/marketplace.json", token))
    release = api_json(f"/repos/{full_name}/releases/latest", token)
    require(not release.get("draft") and not release.get("prerelease"), "latest release is not stable")
    assets = [asset for asset in release.get("assets", []) if asset.get("name") == metadata["package"]]
    require(len(assets) == 1, "latest release is missing the declared package asset")
    package_data = download(assets[0]["browser_download_url"], token)
    manifest = validate_package(package_data)
    require(release.get("tag_name", "").removeprefix("v") == manifest["version"], "release tag does not match plugin version")
    owner = repo["owner"]["login"]
    icon_url = None
    if metadata.get("icon"):
        branch = urllib.parse.quote(repo["default_branch"], safe="")
        icon_path = urllib.parse.quote(metadata["icon"], safe="/")
        icon_url = f"https://raw.githubusercontent.com/{full_name}/{branch}/{icon_path}"
    return {
        "identifier": manifest["identifier"],
        "name": manifest["name"],
        "version": manifest["version"],
        "author": manifest["author"],
        "summary": metadata["summary"],
        "downloadURL": assets[0]["browser_download_url"],
        "sha256": hashlib.sha256(package_data).hexdigest(),
        "repository": repo["html_url"],
        "publisher": owner,
        "iconURL": icon_url,
        "categories": metadata.get("categories", []),
        "permissions": catalog_permissions(manifest),
        "networkHosts": sorted(manifest.get("permissions", {}).get("networkHosts", [])),
        "minimumSideCordVersion": manifest["minimumSideCordVersion"],
        "verifiedPublisher": owner.lower() in verified,
    }


def load_blocklist(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    data = json.loads(path.read_text())
    require(isinstance(data, dict) and data.get("schemaVersion") == 1, "invalid blocklist schema")
    blocks = data.get("blocks", [])
    require(isinstance(blocks, list), "blocklist entries are not a list")
    for block in blocks:
        require(isinstance(block, dict) and IDENTIFIER.fullmatch(block.get("identifier", "")), "invalid block identifier")
        versions = block.get("versions", [])
        require(isinstance(versions, list) and len(versions) == len(set(versions)), "invalid blocked versions")
        require(all(VERSION.fullmatch(value) for value in versions), "invalid blocked version")
        require(isinstance(block.get("reason"), str) and 0 < len(block["reason"]) <= 240, "invalid block reason")
    return blocks


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("public/catalog.json"))
    parser.add_argument("--blocklist", type=Path, default=Path(".sidecord/blocklist.json"))
    args = parser.parse_args()
    token = os.environ.get("GITHUB_TOKEN", "")
    encoded_key = os.environ.get("SIDECORD_CATALOG_SIGNING_KEY", "")
    require(bool(token), "GITHUB_TOKEN is required")
    try:
        private_key_data = base64.b64decode(encoded_key, validate=True)
        private_key = Ed25519PrivateKey.from_private_bytes(private_key_data)
    except (ValueError, TypeError) as error:
        raise RejectedPlugin("SIDECORD_CATALOG_SIGNING_KEY must be a Base64 raw 32-byte Ed25519 private key") from error
    verified = {
        value.strip().lower() for value in os.environ.get("SIDECORD_VERIFIED_PUBLISHERS", "").split(",")
        if value.strip()
    }

    entries_by_identifier: dict[str, list[dict[str, Any]]] = {}
    for repo in discover_repositories(token):
        try:
            entry = build_entry(repo, token, verified)
            entries_by_identifier.setdefault(entry["identifier"], []).append(entry)
        except (RejectedPlugin, urllib.error.HTTPError, urllib.error.URLError, KeyError) as error:
            print(f"Rejected {repo.get('full_name', 'unknown repository')}: {error}", file=sys.stderr)
    duplicates = {identifier for identifier, entries in entries_by_identifier.items() if len(entries) != 1}
    for identifier in sorted(duplicates):
        print(f"Rejected duplicate plugin identifier: {identifier}", file=sys.stderr)
    entries = [
        candidates[0] for identifier, candidates in entries_by_identifier.items()
        if identifier not in duplicates
    ]
    entries.sort(key=lambda entry: (entry["name"].casefold(), entry["identifier"]))
    catalog = {
        "schemaVersion": 2,
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "plugins": entries,
        "blocklist": load_blocklist(args.blocklist),
    }
    payload = json.dumps(catalog, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
    envelope = {
        "payload": base64.b64encode(payload).decode(),
        "signature": base64.b64encode(private_key.sign(payload)).decode(),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(envelope, indent=2, sort_keys=True) + "\n")
    print(f"Published {len(entries)} plugins; rejected {len(duplicates)} duplicate identifiers")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RejectedPlugin as error:
        print(f"Catalog build failed: {error}", file=sys.stderr)
        raise SystemExit(1)
