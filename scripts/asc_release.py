#!/usr/bin/env python3
"""Prepare and submit a TC LMS release in App Store Connect from store/listing.json.

Builds on the ios-auto-release skill's ci_submit.py (JWT, version create/rename,
screenshot replace, build attach, review submission) and adds what a TC LMS
listing needs on every release: name/subtitle/privacy URL, description,
keywords, promo text, support/marketing URLs, What's New (from CHANGELOG.md),
copyright, category, and the App Review contact + sample-account sign-in.

  scripts/asc_release.py prepare --version 1.3 --build 4    # everything but submit
  scripts/asc_release.py submit  --version 1.3 --build 4    # prepare + submit for review
  scripts/asc_release.py status

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH, ASC_BUNDLE_ID (from .env),
APP_REVIEW_EMAIL / APP_REVIEW_PASSWORD / APP_REVIEW_PHONE (gitignored .env only).
"""
import argparse, json, os, sys, time

sys.path.insert(0, os.path.expanduser("~/.claude/skills/ios-auto-release/scripts"))
import ci_submit as asc  # noqa: E402
import http.client, urllib.error  # noqa: E402

# Apple's API intermittently drops connections ("Remote end closed connection").
# Every step here is idempotent, so retry transport failures transparently.
_call = asc.call


def _call_with_retry(*args, **kwargs):
    for attempt in range(6):
        try:
            return _call(*args, **kwargs)
        except (http.client.RemoteDisconnected, urllib.error.URLError, ConnectionError, TimeoutError):
            if attempt == 5:
                raise
            time.sleep(3 * (attempt + 1))


asc.call = _call_with_retry

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_env():
    path = os.path.join(ROOT, ".env")
    if os.path.exists(path):
        for line in open(path):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    os.environ.setdefault("ASC_KEY_ID", "YQHNLVGDWK")
    os.environ.setdefault("ASC_ISSUER_ID", "f026f849-65f1-4ca4-9d49-1b6764131f40")
    os.environ.setdefault("ASC_PRIVATE_KEY_PATH", "~/.appstoreconnect/private_keys/AuthKey_YQHNLVGDWK.p8")


def patch(tok, typ, rid, attrs=None, rels=None, retries=8):
    body = {"data": {"type": typ, "id": rid}}
    if attrs:
        body["data"]["attributes"] = attrs
    if rels:
        body["data"]["relationships"] = rels
    for _ in range(retries):
        s, b = asc.call("PATCH", f"/v1/{typ}/{rid}", body, tok)
        if s < 300:
            return
        if s == 409 and "ENTITY_ERROR" not in b:   # version briefly locked by a cancelled review
            time.sleep(5)
            continue
        sys.exit(f"PATCH {typ}/{rid} failed {s}: {b[:500]}")
    sys.exit(f"PATCH {typ}/{rid} kept failing (locked)")


def app_info(tok, aid):
    s, d = asc.jget("GET", f"/v1/apps/{aid}/appInfos", tok)
    infos = d.get("data", [])
    # The editable appInfo is the one not READY_FOR_DISTRIBUTION/live.
    live = {"READY_FOR_DISTRIBUTION", "READY_FOR_SALE"}
    editable = [i for i in infos if i["attributes"].get("appStoreState", i["attributes"].get("state")) not in live]
    return (editable or infos)[0]


def prepare(a, listing):
    tok = asc.token()
    aid = asc.app_id(tok)
    vid, _created = asc.ensure_version(tok, aid, a.version, None)
    asc.cancel_active(tok, aid)
    print(f"app {aid}, version {a.version} → {vid}")

    # App-level: name, subtitle, privacy policy (appInfoLocalization) + category (appInfo).
    info = app_info(tok, aid)
    s, locs = asc.jget("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations", tok)
    for loc in locs.get("data", []):
        patch(tok, "appInfoLocalizations", loc["id"], {
            "name": listing["name"], "subtitle": listing["subtitle"],
            "privacyPolicyUrl": listing["privacyPolicyUrl"]})
    patch(tok, "appInfos", info["id"], rels={
        "primaryCategory": {"data": {"type": "appCategories", "id": listing["primaryCategory"]}}})
    print("app info: name/subtitle/privacy/category set")

    # Version-level copy.
    first_release = not any(v["attributes"]["appStoreState"] in asc.RELEASED for v in asc.versions(tok, aid))
    for loc in asc.localization(tok, vid):
        attrs = {k: listing[k] for k in ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl")}
        notes = asc.changelog_notes(a.version, os.path.join(ROOT, "CHANGELOG.md"))
        if notes and not first_release:
            attrs["whatsNew"] = notes
        patch(tok, "appStoreVersionLocalizations", loc["id"], attrs)
    patch(tok, "appStoreVersions", vid, {"copyright": listing["copyright"], "releaseType": "AFTER_APPROVAL"})
    print("version localization + copyright set")

    # Screenshots (replace).
    shots = os.path.join(ROOT, "ci/screenshots/APP_IPHONE_67")
    asc.upload_screenshots(tok, vid, shots)

    # App Review contact + sample account.
    review = {
        "contactFirstName": listing["review"]["firstName"], "contactLastName": listing["review"]["lastName"],
        "contactPhone": os.environ["APP_REVIEW_PHONE"], "contactEmail": listing["review"]["email"],
        "demoAccountRequired": True,
        "demoAccountName": os.environ["APP_REVIEW_EMAIL"],
        "demoAccountPassword": os.environ["APP_REVIEW_PASSWORD"],
        "notes": listing["review"]["notes"],
    }
    s, d = asc.jget("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail", tok)
    if s == 200 and d.get("data"):
        patch(tok, "appStoreReviewDetails", d["data"]["id"], review)
    else:
        s, b = asc.call("POST", "/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": review,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}, tok)
        if s >= 300:
            sys.exit(f"review detail failed {s}: {b[:400]}")
    print("App Review contact + sample account set")

    # Build.
    deadline = time.time() + 45 * 60
    while True:
        s, d = asc.jget("GET", f"/v1/builds?filter[app]={aid}&filter[version]={a.build}&limit=5", tok)
        st = d["data"][0]["attributes"]["processingState"] if d.get("data") else "NOT_FOUND"
        if st == "VALID":
            break
        if st in ("FAILED", "INVALID") or time.time() > deadline:
            sys.exit(f"build {a.build} is {st} — see TestFlight → Build Uploads")
        print(f"build {a.build}: {st} … waiting", flush=True)
        time.sleep(30)
        tok = asc.token()
    asc.attach_build(tok, aid, vid, a.build)
    return tok, aid, vid


def status(_a=None):
    tok = asc.token()
    aid = asc.app_id(tok)
    for v in sorted(asc.versions(tok, aid), key=lambda v: asc.vkey(v["attributes"]["versionString"]), reverse=True)[:3]:
        print(v["attributes"]["versionString"], v["attributes"]["appStoreState"])


def main():
    load_env()
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("prepare", "submit"):
        x = sub.add_parser(name)
        x.add_argument("--version", required=True)
        x.add_argument("--build", required=True)
    sub.add_parser("status")
    a = p.parse_args()
    if a.cmd == "status":
        return status()
    listing = json.load(open(os.path.join(ROOT, "store/listing.json")))
    tok, aid, vid = prepare(a, listing)
    if a.cmd == "submit":
        asc.submit_for_review(tok, aid, vid)
        time.sleep(5)
        s, d = asc.jget("GET", f"/v1/appStoreVersions/{vid}", asc.token())
        print("state:", d["data"]["attributes"]["appStoreState"])


if __name__ == "__main__":
    main()
