#!/usr/bin/env python3
"""
Wait for a TestFlight build to finish processing, then assign it to every
tester group — internal and external alike.

Uploading is not distributing. A build lands in App Store Connect, processes to
VALID, and then sits there: testers see nothing until it is attached to a group.
A group only picks builds up on its own when "Automatically distribute new
builds" is on (`hasAccessToAllBuilds`), which is off by default and — this is
the part that matters — can only be set when the group is created. Build 35
uploaded successfully on 2026-08-05 and never reached a tester for exactly that
reason, while the release script printed "Internal testers get it with no
review" — which described the intent, not what had happened.

External groups were skipped here until 2026-08-10, which recreated that same
failure one layer out: the script assigned build 66 to Internal, reported
success, and the external group it had never heard of would have gone on
showing the previous build. A friend on TestFlight is in an external group,
because an internal tester has to be an App Store Connect user first.

An external group also waits for TestFlight App Review, and only for the first
build of each marketing version. Assignment is the same either way; what
differs is that testers on an external group cannot install until the review
passes, so this says which state the build is in rather than implying it is
already downloadable.

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


def api(path: str, method: str = "GET", body: dict | None = None, attempts: int = 1) -> dict:
    """One call, retried only where App Store Connect is known to lag itself.

    Adding a build to a group can answer 404 "no resource of type 'builds' with
    id …" for the build the same API returned as VALID seconds earlier: the
    relationship endpoint reads a store that has not caught up. It happened on
    build 66 and cleared on its own minutes later, having exited non-zero and
    told a human to re-run — which is a retry with extra steps.
    """
    for attempt in range(1, attempts + 1):
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
            # Only 404 and 409, and only while attempts remain: a 401 is a bad
            # key and a 422 is a bad request, and both mean the same thing on
            # the fifth try as on the first.
            if attempt < attempts and error.code in (404, 409):
                print(f"    App Store Connect is not ready yet; retrying in 60s ({attempt})")
                time.sleep(60)
                continue
            raise SystemExit(f"testflight-assign: HTTP {error.code} on {path}\n{detail}")
    raise SystemExit("testflight-assign: unreachable")


def waiting_on(internal: bool, external_state: str | None) -> str:
    """What an external group is still waiting for, in the same line as the
    assignment — because "assigned" reads as "they have it", and on an external
    group that is only true once TestFlight App Review has passed.

    Review is per marketing version, not per build: the first build of a new
    `MARKETING_VERSION` queues, and every build after it on that version is
    installable within minutes of this line being printed.
    """
    if internal:
        return ""
    return {
        "WAITING_FOR_BETA_REVIEW": " — external testers wait for TestFlight App Review",
        "IN_BETA_REVIEW": " — external testers wait; review is in progress",
        "BETA_REJECTED": " — REJECTED by TestFlight App Review; nobody external can install it",
        "EXPIRED": " — expired; external testers cannot install it",
    }.get(external_state or "", " — live for external testers")


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

    groups = api(f"/v1/betaGroups?filter[app]={app_id}&limit=50")["data"]
    if not groups:
        raise SystemExit(
            "testflight-assign: no tester group exists. Create one in "
            "App Store Connect → TestFlight."
        )

    # Said once, from the build itself, rather than guessed per group. An
    # external group's testers wait on this state and an internal group's do
    # not, and the difference is the whole reason the line is printed.
    external_state = api(f"/v1/builds/{build['id']}/buildBetaDetail")["data"]["attributes"].get(
        "externalBuildState"
    )

    for group in groups:
        name = group["attributes"]["name"]
        internal = bool(group["attributes"].get("isInternalGroup"))
        # Read the group's own build list to confirm. The reverse relationship
        # (`/v1/builds/{id}/betaGroups`) returns an empty set even for builds
        # that are demonstrably in a group, so it cannot be used to verify.
        already = [
            item["attributes"]["version"]
            for item in api(f"/v1/betaGroups/{group['id']}/builds?limit=200").get("data", [])
        ]
        if build_number in already:
            print(f"    build {build_number} already in '{name}'{waiting_on(internal, external_state)}")
            continue
        api(
            f"/v1/betaGroups/{group['id']}/relationships/builds",
            "POST",
            {"data": [{"type": "builds", "id": build["id"]}]},
            attempts=5,
        )
        confirmed = [
            item["attributes"]["version"]
            for item in api(f"/v1/betaGroups/{group['id']}/builds?limit=200").get("data", [])
        ]
        if build_number in confirmed:
            print(
                f"    assigned build {build_number} to '{name}'"
                f"{waiting_on(internal, external_state)}"
            )
        else:
            raise SystemExit(
                f"testflight-assign: POST succeeded but build {build_number} is not in "
                f"'{name}'. Assign it by hand in App Store Connect."
            )


if __name__ == "__main__":
    main()
