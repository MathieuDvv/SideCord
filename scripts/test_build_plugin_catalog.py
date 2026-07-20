#!/usr/bin/env python3

import json
import unittest

import build_plugin_catalog as catalog


def package(*, javascript=False, hosts=None):
    hosts = hosts or ["music.example.com"]
    manifest = {
        "schemaVersion": 2,
        "identifier": "com.example.music",
        "name": "Example Music",
        "version": "1.2.4",
        "author": "Descriptive Author",
        "description": "A compact music panel.",
        "minimumSideCordVersion": "2.5.0",
        "capabilities": ["webPanel"],
        "permissions": {
            "networkHosts": hosts,
            "persistentWebsiteData": True,
            "backgroundAudio": True,
        },
        "contributions": {
            "webPanels": [{
                "id": "music-panel",
                "name": "Music",
                "placement": "bottom",
                "initialURL": "https://music.example.com/",
                "allowedNavigationHosts": hosts,
            }]
        },
    }
    if javascript:
        manifest["javascript"] = "alert(1)"
    return json.dumps({"manifest": manifest}).encode()


class CatalogValidationTests(unittest.TestCase):
    def test_accepts_discovery_metadata_and_declarative_package(self):
        metadata = catalog.validate_metadata(json.dumps({
            "schemaVersion": 1,
            "package": "example.sidecord-plugin.json",
            "icon": "assets/icon.png",
            "categories": ["music", "web-panel"],
            "summary": "Compact example player",
        }).encode())
        manifest = catalog.validate_package(package())

        self.assertEqual(metadata["package"], "example.sidecord-plugin.json")
        self.assertEqual(
            catalog.catalog_permissions(manifest),
            ["backgroundAudio", "persistentWebsiteData", "webPanel"],
        )

    def test_rejects_plugin_supplied_javascript(self):
        with self.assertRaisesRegex(catalog.RejectedPlugin, "forbidden executable field"):
            catalog.validate_package(package(javascript=True))

    def test_rejects_wildcard_network_hosts(self):
        with self.assertRaisesRegex(catalog.RejectedPlugin, "wildcard hosts"):
            catalog.validate_package(package(hosts=["*.example.com"]))

    def test_rejects_unsafe_metadata_package_path(self):
        with self.assertRaisesRegex(catalog.RejectedPlugin, "package must name"):
            catalog.validate_metadata(json.dumps({
                "schemaVersion": 1,
                "package": "../plugin.json",
                "summary": "Unsafe path",
            }).encode())


if __name__ == "__main__":
    unittest.main()
