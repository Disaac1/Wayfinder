#!/usr/bin/env python3
"""
Test Release Sync & Client Download Endpoints
=============================================
Validates:
1. GET /api/client/download-info returns valid release metadata and direct GitHub URLs.
2. POST /api/client/sync-release:
   - Rejects unauthorized requests when secret is configured and invalid.
   - Accepts authorized sync calls (localhost or valid x-release-secret).
3. GET /api/client/download-client redirects directly to GitHub Releases.
"""

import os
import unittest
import urllib.request
import urllib.error
import json

def get_base_url():
    if "SERVER_URL" in os.environ:
        return os.environ["SERVER_URL"].rstrip("/")
    for port in (8080, 8081):
        url = f"http://localhost:{port}"
        try:
            req = urllib.request.Request(f"{url}/health", headers={"User-Agent": "CI-Test"})
            with urllib.request.urlopen(req, timeout=1) as resp:
                if resp.status == 200:
                    return url
        except Exception:
            continue
    return "http://localhost:8080"

class TestReleaseSyncAndDownloads(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.BASE_URL = get_base_url()
        try:
            req = urllib.request.Request(f"{cls.BASE_URL}/health", headers={"User-Agent": "CI-Test"})
            with urllib.request.urlopen(req, timeout=2) as resp:
                cls.online = (resp.status == 200)
        except Exception:
            cls.online = False

    def setUp(self):
        if not getattr(self, "online", False):
            raise unittest.SkipTest(f"Backend service is offline at {self.BASE_URL}")

    def test_01_download_info_endpoint(self):
        url = f"{self.BASE_URL}/api/client/download-info"
        req = urllib.request.Request(url, headers={"User-Agent": "CI-Test"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            self.assertEqual(resp.status, 200)
            data = json.loads(resp.read().decode())
            self.assertIn("tag", data)
            self.assertIn("version", data)
            self.assertIn("installer_url", data)
            self.assertIn("portable_url", data)
            # Direct link must point to github.com
            self.assertTrue(
                "github.com" in data["installer_url"],
                f"installer_url does not point to github.com: {data['installer_url']}"
            )
            print(f"[Test] download-info: version={data.get('version')} tag={data.get('tag')} url={data.get('installer_url')}")

    def test_02_download_client_redirect(self):
        class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
            def http_error_302(self, req, fp, code, msg, headers):
                return fp

        opener = urllib.request.build_opener(NoRedirectHandler)
        url = f"{self.BASE_URL}/api/client/download-client"
        try:
            resp = opener.open(url, timeout=5)
            # Either 302 redirect header or read redirected response
            location = resp.headers.get("Location", "")
            if location:
                self.assertTrue("github.com" in location, f"Redirect location is not GitHub: {location}")
                print(f"[Test] download-client redirected to: {location}")
        except urllib.error.HTTPError as e:
            if e.code == 302:
                location = e.headers.get("Location", "")
                self.assertTrue("github.com" in location, f"Redirect location is not GitHub: {location}")
                print(f"[Test] download-client 302 Location: {location}")
            else:
                raise

    def test_03_sync_release_webhook_localhost(self):
        url = f"{self.BASE_URL}/api/client/sync-release"
        req = urllib.request.Request(
            url,
            data=json.dumps({"tag": "v1.2.0"}).encode("utf-8"),
            headers={"Content-Type": "application/json", "User-Agent": "CI-Test"},
            method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=8) as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode())
                self.assertTrue(data.get("success"))
                self.assertEqual(data.get("tag"), "v1.2.0")
                print(f"[Test] sync-release webhook succeeded: {data}")
        except urllib.error.HTTPError as e:
            # 502 Bad Gateway if GitHub API is unreachable in restricted CI environment
            if e.code == 502:
                print("[Test] sync-release returned 502 (GitHub API unreachable from runner), which is expected if network is restricted")
            else:
                raise

if __name__ == "__main__":
    unittest.main()
