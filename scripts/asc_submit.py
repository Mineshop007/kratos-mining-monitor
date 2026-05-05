#!/usr/bin/env python3
"""
App Store Connect API helper for Kratos.

Usage:
  scripts/asc_submit.py status              # show app + builds + versions state
  scripts/asc_submit.py create-version 1.4.0
  scripts/asc_submit.py wait-for-build 14   # poll until build is processed
  scripts/asc_submit.py attach-build 1.4.0 14
  scripts/asc_submit.py set-release-notes 1.4.0 "..."
  scripts/asc_submit.py submit 1.4.0        # FINAL — submits to App Store review

Auth: uses ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8.
Submit role key (FP975TFYQ8) is required for create-version / submit.
"""
from __future__ import annotations
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

try:
    import jwt  # PyJWT
    import requests
except ImportError:
    print("Install deps: pip3 install PyJWT cryptography requests", file=sys.stderr)
    sys.exit(1)


KEY_ID = "FP975TFYQ8"               # App Manager — submit
ISSUER_ID = "d9331e79-b93d-4be2-bd25-124d9d6dd2f2"
APP_ID = "6762138440"               # Kratos
BUNDLE_ID = "com.kratos.miningmonitor"
KEY_FILE = Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{KEY_ID}.p8"

API = "https://api.appstoreconnect.apple.com/v1"


def make_jwt() -> str:
    if not KEY_FILE.exists():
        sys.exit(f"missing key: {KEY_FILE}")
    private_key = KEY_FILE.read_text()
    now = datetime.now(timezone.utc)
    payload = {
        "iss": ISSUER_ID,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=15)).timestamp()),
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key,
                       algorithm="ES256",
                       headers={"kid": KEY_ID, "typ": "JWT"})


def headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {make_jwt()}",
        "Content-Type": "application/json",
    }


def call(method: str, path: str, body: dict | None = None) -> dict:
    url = f"{API}/{path}" if not path.startswith("http") else path
    r = requests.request(method, url, headers=headers(),
                         data=json.dumps(body) if body else None,
                         timeout=30)
    if not r.ok:
        sys.exit(f"{method} {url} → {r.status_code}\n{r.text}")
    if r.status_code == 204 or not r.content:
        return {}
    return r.json()


# ── commands ──────────────────────────────────────────────────────────────────

def cmd_status() -> None:
    print("APP")
    app = call("GET", f"apps/{APP_ID}")
    print(f"  id={app['data']['id']}  bundle={app['data']['attributes']['bundleId']}")
    print(f"  name={app['data']['attributes']['name']}")
    print()
    print("RECENT BUILDS")
    bs = call("GET", f"builds?filter[app]={APP_ID}&sort=-uploadedDate&limit=10")
    for b in bs.get("data", []):
        a = b["attributes"]
        print(f"  build {a['version']:>4}  v{a.get('preReleaseVersion', {}) or '?'}  "
              f"state={a.get('processingState'):>12}  "
              f"valid={'✓' if a.get('valid') else '✗'}  "
              f"uploaded={a.get('uploadedDate', '')[:19]}")
    print()
    print("APP STORE VERSIONS")
    vs = call("GET", f"apps/{APP_ID}/appStoreVersions?limit=10")
    for v in vs.get("data", []):
        a = v["attributes"]
        print(f"  v{a['versionString']:>6}  state={a.get('appStoreState'):>20}  "
              f"platform={a.get('platform')}  released={a.get('releaseType')}")


def cmd_wait_for_build(build_number: str, version_label: str = "1.4.0",
                       timeout_min: int = 30) -> None:
    print(f"Waiting for build {build_number} (v{version_label}) to finish processing…")
    deadline = time.time() + timeout_min * 60
    while time.time() < deadline:
        bs = call("GET",
                  f"builds?filter[app]={APP_ID}&filter[version]={build_number}"
                  f"&include=preReleaseVersion&limit=10")
        match = None
        for b in bs.get("data", []):
            pre_id = b.get("relationships", {}).get(
                "preReleaseVersion", {}).get("data", {}).get("id")
            for inc in bs.get("included", []):
                if inc["id"] == pre_id and inc["attributes"]["version"] == version_label:
                    match = b
                    break
        if match:
            state = match["attributes"]["processingState"]
            print(f"  state={state}  valid={match['attributes'].get('valid')}")
            if state == "VALID":
                print("OK — build is processed.")
                return
        else:
            print(f"  not yet visible…")
        time.sleep(20)
    sys.exit("Timed out waiting for build.")


def find_or_create_version(version_label: str) -> str:
    vs = call("GET", f"apps/{APP_ID}/appStoreVersions"
                     f"?filter[versionString]={version_label}")
    for v in vs.get("data", []):
        if v["attributes"]["versionString"] == version_label:
            print(f"version {version_label} already exists: {v['id']}")
            return v["id"]
    print(f"creating version {version_label}…")
    r = call("POST", "appStoreVersions", body={
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": "IOS",
                "versionString": version_label,
                "releaseType": "MANUAL",
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP_ID}},
            },
        },
    })
    return r["data"]["id"]


def cmd_create_version(version_label: str) -> None:
    vid = find_or_create_version(version_label)
    print(f"version id: {vid}")


def cmd_attach_build(version_label: str, build_number: str) -> None:
    vid = find_or_create_version(version_label)
    bs = call("GET",
              f"builds?filter[app]={APP_ID}&filter[version]={build_number}"
              f"&include=preReleaseVersion")
    bid = None
    for b in bs.get("data", []):
        pre_id = b.get("relationships", {}).get(
            "preReleaseVersion", {}).get("data", {}).get("id")
        for inc in bs.get("included", []):
            if inc["id"] == pre_id and inc["attributes"]["version"] == version_label:
                bid = b["id"]
                break
    if bid is None:
        sys.exit(f"no build {build_number} for v{version_label} found.")
    call("PATCH", f"appStoreVersions/{vid}/relationships/build", body={
        "data": {"type": "builds", "id": bid},
    })
    print(f"attached build {bid} → version {vid}")


def cmd_set_release_notes(version_label: str, text: str,
                          locale: str = "en-US") -> None:
    vid = find_or_create_version(version_label)
    locs = call("GET", f"appStoreVersions/{vid}/appStoreVersionLocalizations")
    loc_id = None
    for l in locs.get("data", []):
        if l["attributes"]["locale"] == locale:
            loc_id = l["id"]
            break
    if loc_id is None:
        r = call("POST", "appStoreVersionLocalizations", body={
            "data": {
                "type": "appStoreVersionLocalizations",
                "attributes": {"locale": locale},
                "relationships": {
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": vid},
                    },
                },
            },
        })
        loc_id = r["data"]["id"]
    call("PATCH", f"appStoreVersionLocalizations/{loc_id}", body={
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": loc_id,
            "attributes": {"whatsNew": text},
        },
    })
    print(f"release notes saved to version {version_label} / {locale}")


def cmd_submit(version_label: str) -> None:
    vid = find_or_create_version(version_label)
    print(f"creating reviewSubmission for version {vid}…")
    sub = call("POST", "reviewSubmissions", body={
        "data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP_ID}},
            },
        },
    })
    sub_id = sub["data"]["id"]
    print(f"  submission id: {sub_id}")
    item = call("POST", "reviewSubmissionItems", body={
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {
                    "data": {"type": "reviewSubmissions", "id": sub_id},
                },
                "appStoreVersion": {
                    "data": {"type": "appStoreVersions", "id": vid},
                },
            },
        },
    })
    print(f"  item id: {item['data']['id']}")
    call("PATCH", f"reviewSubmissions/{sub_id}", body={
        "data": {
            "type": "reviewSubmissions",
            "id": sub_id,
            "attributes": {"submitted": True},
        },
    })
    print(f"SUBMITTED v{version_label} for review.")


# ── main ──────────────────────────────────────────────────────────────────────

def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 1
    cmd = argv[1]
    if cmd == "status":
        cmd_status()
    elif cmd == "create-version" and len(argv) >= 3:
        cmd_create_version(argv[2])
    elif cmd == "wait-for-build" and len(argv) >= 3:
        cmd_wait_for_build(argv[2])
    elif cmd == "attach-build" and len(argv) >= 4:
        cmd_attach_build(argv[2], argv[3])
    elif cmd == "set-release-notes" and len(argv) >= 4:
        cmd_set_release_notes(argv[2], argv[3])
    elif cmd == "submit" and len(argv) >= 3:
        cmd_submit(argv[2])
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
