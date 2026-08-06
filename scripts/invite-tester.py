#!/usr/bin/env python3
"""
Add one friend to TestFlight, by email, with nothing for them to configure.

  ./scripts/invite-tester.py andy@example.com [First] [Last]

Since recognition stopped needing a per-person token, this is the entire
onboarding: they accept, install, and the id their phone generates on first
launch is what keeps their meals and photos apart from everyone else's.

Internal testing is what this account has, and an internal tester must be an
App Store Connect user first — Apple offers no way around that. So the work is
two calls in sequence, and the second one cannot happen until a human clicks a
link in their mail:

  1. invite them as a user, limited to this app, with no provisioning rights;
  2. once they have accepted, add them to every internal tester group.

Re-running is how you finish step 2. The script is idempotent — an existing
user, a pending invitation, and an already-added tester are all reported and
skipped rather than duplicated — so the normal use is to run it, tell them to
check their mail, and run it again afterwards.

Credentials are discovered exactly as release-testflight.sh discovers them: the
key id from the AuthKey_*.p8 filename, the issuer id from
~/.appstoreconnect/issuer_id. Both can be overridden with ASC_KEY_ID and
ASC_ISSUER_ID. Needs an Admin key — inviting users is an Admin action, and a
Developer key returns 403 here while working fine for build assignment.

Requires `pyjwt` and `cryptography`:  pip3 install --user pyjwt cryptography
"""

from __future__ import annotations  # macOS ships python3.9; `dict | None` is 3.10+

import glob
import json
import os
import sys
import urllib.error
import urllib.request
import time

try:
    import jwt  # PyJWT
except ImportError:
    sys.stderr.write(
        "invite-tester: needs PyJWT and cryptography.\n"
        "  pip3 install --user pyjwt cryptography\n"
    )
    sys.exit(2)

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "app.shaman.tracker")
KEY_DIR = os.environ.get("ASC_KEY_DIR", os.path.expanduser("~/.appstoreconnect/private_keys"))
ISSUER_FILE = os.environ.get("ASC_ISSUER_FILE", os.path.expanduser("~/.appstoreconnect/issuer_id"))


def credentials() -> tuple[str, str, str]:
    key_id = os.environ.get("ASC_KEY_ID", "")
    if not key_id:
        # Exactly one key is the normal case; with several, name the one you want.
        found = glob.glob(os.path.join(KEY_DIR, "AuthKey_*.p8"))
        if len(found) == 1:
            key_id = os.path.basename(found[0])[len("AuthKey_") : -len(".p8")]
    issuer = os.environ.get("ASC_ISSUER_ID", "")
    if not issuer and os.path.exists(ISSUER_FILE):
        with open(ISSUER_FILE) as handle:
            issuer = handle.read().strip()
    key_path = os.environ.get("ASC_KEY_PATH", os.path.join(KEY_DIR, f"AuthKey_{key_id}.p8"))
    if not (key_id and issuer and os.path.exists(key_path)):
        raise SystemExit(
            "invite-tester: no App Store Connect credentials.\n"
            f"  put an Admin AuthKey_*.p8 in {KEY_DIR}\n"
            f"  and the issuer UUID in {ISSUER_FILE}"
        )
    return key_id, issuer, key_path


KEY_ID, ISSUER, KEY_PATH = credentials()


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
        detail = error.read().decode()[:600]
        raise SystemExit(f"invite-tester: HTTP {error.code} on {path}\n{detail}")


def matches(record: dict, email: str) -> bool:
    attributes = record["attributes"]
    for field in ("username", "email"):
        value = attributes.get(field)
        if value and value.lower() == email:
            return True
    return False


def main() -> None:
    if not 2 <= len(sys.argv) <= 4:
        raise SystemExit("usage: invite-tester.py <email> [first-name] [last-name]")
    email = sys.argv[1].strip().lower()
    if "@" not in email:
        raise SystemExit(f"invite-tester: {email!r} is not an email address")
    # Apple demands both names. Neither is shown to the tester — they appear in
    # Users and Access, where you can correct them — so the local part is a
    # better default than a guess at somebody's real name.
    first = sys.argv[2] if len(sys.argv) > 2 else email.split("@")[0]
    last = sys.argv[3] if len(sys.argv) > 3 else "Tester"

    apps = api(f"/v1/apps?filter[bundleId]={BUNDLE_ID}&limit=1")["data"]
    if not apps:
        raise SystemExit(f"invite-tester: no app record for bundle id {BUNDLE_ID}")
    app_id = apps[0]["id"]

    users = [u for u in api("/v1/users?limit=200")["data"] if matches(u, email)]
    invitations = [i for i in api("/v1/userInvitations?limit=200")["data"] if matches(i, email)]

    if users:
        print(f"    {email} is already an App Store Connect user")
    elif invitations:
        print(f"    {email} was already invited and has not accepted yet")
    else:
        api(
            "/v1/userInvitations",
            "POST",
            {
                "data": {
                    "type": "userInvitations",
                    "attributes": {
                        "email": email,
                        "firstName": first,
                        "lastName": last,
                        "roles": ["DEVELOPER"],
                        # This app only, and no certificate or profile rights:
                        # a tester needs to install builds, nothing else.
                        "allAppsVisible": False,
                        "provisioningAllowed": False,
                    },
                    "relationships": {
                        "visibleApps": {"data": [{"type": "apps", "id": app_id}]}
                    },
                }
            },
        )
        print(f"    invited {email} as a Developer on this app only")

    groups = [
        group
        for group in api(f"/v1/betaGroups?filter[app]={app_id}&limit=50")["data"]
        if group["attributes"].get("isInternalGroup")
    ]
    if not groups:
        raise SystemExit(
            "invite-tester: no internal tester group exists. Create one in "
            "App Store Connect → TestFlight → Internal Testing."
        )

    pending = False
    for group in groups:
        name = group["attributes"]["name"]
        existing = api(f"/v1/betaGroups/{group['id']}/betaTesters?limit=200").get("data", [])
        if any(matches(tester, email) for tester in existing):
            print(f"    already a tester in '{name}'")
            continue
        try:
            api(
                "/v1/betaTesters",
                "POST",
                {
                    "data": {
                        "type": "betaTesters",
                        "attributes": {"email": email, "firstName": first, "lastName": last},
                        "relationships": {
                            "betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}
                        },
                    }
                },
            )
            print(f"    added to '{name}'")
        except SystemExit as error:
            # The one failure that is not a failure: an internal group takes
            # only accepted users, so this is expected on the first run.
            if "409" in str(error) or "403" in str(error):
                pending = True
                print(f"    cannot add to '{name}' until the user invitation is accepted")
            else:
                raise

    print()
    if pending or not users:
        print(f"Tell {email} to accept the App Store Connect invitation in their mail,")
        print("then run this again to finish adding them to the tester group:")
        print(f"  ./scripts/invite-tester.py {email}")
    else:
        print(f"{email} is set up. They install TestFlight, accept the build invitation,")
        print("and that is the whole of it — there is nothing for them to configure.")


if __name__ == "__main__":
    main()
