#!/usr/bin/env python3
"""
Wait for a TestFlight build to finish processing, then assign it to every
internal tester group.

Uploading is not distributing. A build lands in App Store Connect, processes to
VALID, and then sits there: internal testers see nothing until it is attached to
a group. A group only picks builds up on its own when "Automatically distribute
new builds" is on (`hasAccessToAllBuilds`), and it is off by default. Build 35
uploaded successfully on 2026-08-05 and never reached a tester for exactly that
reason, while the release script printed "Internal testers get it with no
review" — which described the intent, not what had happened.

  ./scripts/testflight-assign.py <bundle-id> <build-number>

Reads ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH from the environment; the
release script resolves those before calling. Requires `pyjwt` and
`cryptography`; exits 2 (distinct from a real failure) if they are missing, so
the caller can report the upload as succeeded and the assignment as skipped.
"""

from __future__ import annotations  # macOS ships python3.9; `dict | None` is 3.10+

import json
import os
import sys
import time
import urllib.error
import urllib.request

try:
    import jwt  # PyJWT
except ImportError:
    sys.stderr.write(
        "testflight-assign: needs PyJWT and cryptography.\n"
        "  pip3 install --user pyjwt cryptography\n"
    )
    sys.exit(2)

API = "https://api.appstoreconnect.apple.com"
KEY_ID = os.environ.get("ASC_KEY_ID", "")
ISSUER = os.environ.get("ASC_ISSUER_ID", "")
KEY_PATH = os.environ.get("ASC_KEY_PATH", "")


def token() -> str:
    """Short-lived ES256 JWT. Apple caps the lifetime at 20 minutes."""
    now = int(time.time())
    with open(KEY_PATH) as handle:
        secret = handle.read()
    return jwt.encode(
        {"iss": ISSUER, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        secret,
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def api(path: str, method: str = "GET", body: dict | None = None) -> dict:
    request = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
    )
    try:
        return json.loads(urllib.request.urlopen(request, timeout=60).read() or b"{}")
    except urllib.error.HTTPError as error:
        detail = error.read().decode()[:400]
        raise SystemExit(f"testflight-assign: HTTP {error.code} on {path}\n{detail}")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: testflight-assign.py <bundle-id> <build-number>")
    bundle_id, build_number = sys.argv[1], sys.argv[2]
    if not (KEY_ID and ISSUER and KEY_PATH):
        raise SystemExit(
            "testflight-assign: ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH must all be set."
        )

    apps = api(f"/v1/apps?filter[bundleId]={bundle_id}&limit=1")["data"]
    if not apps:
        raise SystemExit(f"testflight-assign: no app record for bundle id {bundle_id}")
    app_id = apps[0]["id"]

    # Processing usually finishes in a couple of minutes; a build cannot be
    # assigned before it reaches VALID, so poll rather than fail on the race.
    build = None
    for attempt in range(40):
        found = api(
            f"/v1/builds?filter[app]={app_id}&filter[version]={build_number}&limit=1"
        )["data"]
        if found:
            state = found[0]["attributes"]["processingState"]
            if state == "VALID":
                build = found[0]
                break
            if state in ("INVALID", "FAILED"):
                raise SystemExit(
                    f"testflight-assign: build {build_number} finished as {state}; "
                    "check the email from App Store Connect for the reason."
                )
        if attempt == 0:
            print(f"    waiting for build {build_number} to finish processing...")
        time.sleep(15)
    if build is None:
        raise SystemExit(
            f"testflight-assign: build {build_number} did not reach VALID within 10 minutes. "
            "It may still be processing — re-run this script alone to finish the assignment."
        )

    groups = [
        group
        for group in api(f"/v1/betaGroups?filter[app]={app_id}&limit=50")["data"]
        if group["attributes"].get("isInternalGroup")
    ]
    if not groups:
        raise SystemExit(
            "testflight-assign: no internal tester group exists. Create one in "
            "App Store Connect → TestFlight → Internal Testing."
        )

    for group in groups:
        name = group["attributes"]["name"]
        # Read the group's own build list to confirm. The reverse relationship
        # (`/v1/builds/{id}/betaGroups`) returns an empty set even for builds
        # that are demonstrably in a group, so it cannot be used to verify.
        already = [
            item["attributes"]["version"]
            for item in api(f"/v1/betaGroups/{group['id']}/builds?limit=200").get("data", [])
        ]
        if build_number in already:
            print(f"    build {build_number} already in '{name}'")
            continue
        api(
            f"/v1/betaGroups/{group['id']}/relationships/builds",
            "POST",
            {"data": [{"type": "builds", "id": build["id"]}]},
        )
        confirmed = [
            item["attributes"]["version"]
            for item in api(f"/v1/betaGroups/{group['id']}/builds?limit=200").get("data", [])
        ]
        if build_number in confirmed:
            print(f"    assigned build {build_number} to '{name}'")
        else:
            raise SystemExit(
                f"testflight-assign: POST succeeded but build {build_number} is not in "
                f"'{name}'. Assign it by hand in App Store Connect."
            )


if __name__ == "__main__":
    main()
