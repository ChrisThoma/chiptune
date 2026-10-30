#!/usr/bin/env python3
"""Sync Chiptune's Play Store listing, and optionally a bundle, through the
Google Play Developer API.

Reads the fastlane `supply` layout in android/fastlane/metadata/android/, so
the same files work with `fastlane supply` if it is ever installed. Every run
opens one edit, applies all changes to it, and commits it at the end; --check
prints what the API holds and what would change, then discards the edit.

    python3 android/Tools/play/play_sync.py --check
    python3 android/Tools/play/play_sync.py                 # text, details, images
    python3 android/Tools/play/play_sync.py --bundle app-release.aab --track internal

The key defaults to ~/.config/google-play/publisher.json (PLAY_KEY overrides).
Needs pyjwt and cryptography; run without `python3 -I` so they are found.
"""
import argparse
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

PKG = "dev.individuation.chiptune"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
META = os.path.join(ROOT, "fastlane", "metadata", "android")
KEY = os.environ.get("PLAY_KEY", os.path.expanduser("~/.config/google-play/publisher.json"))
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PKG}"

# Contact details shown on the listing (edits.details). Category and privacy
# policy URL are not in the API and are set in Play Console.
DETAILS = {
    "contactEmail": "mail@individuation.dev",
    "contactWebsite": "https://individuation.dev/projects/chiptune/",
}

# Local image folder or file -> Play image type.
IMAGES = [
    ("icon.png", "icon"),
    ("featureGraphic.png", "featureGraphic"),
    ("phoneScreenshots", "phoneScreenshots"),
    ("sevenInchScreenshots", "sevenInchScreenshots"),
    ("tenInchScreenshots", "tenInchScreenshots"),
]


def token():
    k = json.load(open(KEY))
    now = int(time.time())
    assertion = jwt.encode(
        {"iss": k["client_email"], "scope": "https://www.googleapis.com/auth/androidpublisher",
         "aud": k["token_uri"], "iat": now, "exp": now + 3000},
        k["private_key"], algorithm="RS256")
    body = urllib.parse.urlencode(
        {"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion}).encode()
    return json.load(urllib.request.urlopen(k["token_uri"], body))["access_token"]


class Play:
    def __init__(self):
        self.tok = token()

    def call(self, method, url, body=None, data=None, ctype="application/json", missing_ok=False):
        if body is not None:
            data = json.dumps(body).encode()
        for attempt in range(5):
            req = urllib.request.Request(url, method=method, data=data, headers={
                "Authorization": f"Bearer {self.tok}", "Content-Type": ctype})
            try:
                r = urllib.request.urlopen(req, timeout=600)
                raw = r.read()
                return json.loads(raw) if raw else {}
            except urllib.error.HTTPError as e:
                err = e.read().decode(errors="replace")
                # The API answers the odd call with a bare 503; retry those.
                if e.code in (500, 502, 503, 504) and attempt < 4:
                    time.sleep(2 * (attempt + 1))
                    continue
                # A language with no listing yet answers 404; to the caller that's an empty listing.
                if e.code == 404 and missing_ok:
                    return {}
                raise SystemExit(f"{method} {url}\n-> {e.code} {err}")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read().strip("\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="show differences, change nothing")
    ap.add_argument("--no-images", action="store_true")
    ap.add_argument("--bundle", help="path to a signed .aab to upload")
    ap.add_argument("--track", default="internal")
    args = ap.parse_args()

    p = Play()
    edit = p.call("POST", f"{API}/edits", {})["id"]
    e = f"{API}/edits/{edit}"
    changed = []

    details = p.call("GET", f"{e}/details")
    want = {**details, **DETAILS}
    if any(details.get(k) != v for k, v in DETAILS.items()):
        changed.append(f"details: {DETAILS}")
        if not args.check:
            p.call("PUT", f"{e}/details", want)

    for lang in sorted(os.listdir(META)):
        d = os.path.join(META, lang)
        if not os.path.isdir(d):
            continue
        listing = {"language": lang,
                   "title": read(f"{d}/title.txt"),
                   "shortDescription": read(f"{d}/short_description.txt"),
                   "fullDescription": read(f"{d}/full_description.txt")}
        have = p.call("GET", f"{e}/listings/{lang}", missing_ok=True)
        diff = [k for k in ("title", "shortDescription", "fullDescription") if have.get(k) != listing[k]]
        if diff:
            changed.append(f"{lang} listing: {', '.join(diff)}")
            if not args.check:
                p.call("PUT", f"{e}/listings/{lang}", listing)

        if args.no_images:
            continue
        for name, kind in IMAGES:
            src = os.path.join(d, "images", name)
            if os.path.isdir(src):
                files = sorted(os.path.join(src, f) for f in os.listdir(src) if f.lower().endswith(".png"))
            elif os.path.isfile(src):
                files = [src]
            else:
                continue
            if not files:
                continue
            have = p.call("GET", f"{e}/listings/{lang}/{kind}", missing_ok=True).get("images", [])
            changed.append(f"{lang} {kind}: {len(have)} on Play -> {len(files)} local")
            if args.check:
                continue
            p.call("DELETE", f"{e}/listings/{lang}/{kind}")
            for f in files:
                with open(f, "rb") as fh:
                    p.call("POST", f"{UPLOAD}/edits/{edit}/listings/{lang}/{kind}?uploadType=media",
                           data=fh.read(), ctype="image/png")

    if args.bundle:
        changed.append(f"bundle {os.path.basename(args.bundle)} -> {args.track}")
        if not args.check:
            with open(args.bundle, "rb") as fh:
                b = p.call("POST", f"{UPLOAD}/edits/{edit}/bundles?uploadType=media",
                           data=fh.read(), ctype="application/octet-stream")
            code = b["versionCode"]
            notes = os.path.join(META, "en-US", "changelogs", f"{code}.txt")
            release = {"versionCodes": [str(code)], "status": "draft"}
            if os.path.exists(notes):
                release["releaseNotes"] = [{"language": "en-US", "text": read(notes)}]
            p.call("PUT", f"{e}/tracks/{args.track}", {"track": args.track, "releases": [release]})
            changed.append(f"uploaded versionCode {code} as a draft release on {args.track}")

    print("\n".join(changed) if changed else "nothing to change")
    if args.check:
        p.call("DELETE", e)
        print("check only: edit discarded")
    else:
        p.call("POST", f"{e}:commit")
        print("committed")


if __name__ == "__main__":
    main()
