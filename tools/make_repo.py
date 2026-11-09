#!/usr/bin/env python3
"""Regenerate the Sileo/Cydia repository index (docs/Packages) from GitHub releases.

Each published release that carries a .deb asset becomes one stanza. The package
is referenced by its absolute release download URL, so no binaries live in git.
"""
import gzip
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

REPO = os.environ.get("GITHUB_REPOSITORY", "mody-iq/CopyMod")
OWNER, NAME = REPO.split("/")
PAGES = "https://%s.github.io/%s" % (OWNER, NAME)
# raw.githubusercontent.com serves the index and assets immediately, even
# before GitHub Pages has been enabled for the repository.
RAW = "https://raw.githubusercontent.com/%s/main/docs" % REPO

# Fields worth carrying from the deb control file, in output order.
CONTROL_FIELDS = [
    "Package", "Name", "Version", "Architecture", "Description",
    "Maintainer", "Author", "Section", "Depends", "Installed-Size",
]


def releases():
    out = subprocess.check_output(
        ["gh", "api", "--paginate", "repos/%s/releases" % REPO], text=True)
    # --paginate concatenates JSON arrays; join them into one list.
    decoder = json.JSONDecoder()
    items, idx = [], 0
    out = out.strip()
    while idx < len(out):
        obj, end = decoder.raw_decode(out, idx)
        items.extend(obj if isinstance(obj, list) else [obj])
        idx = end
        while idx < len(out) and out[idx] in " \t\r\n":
            idx += 1
    return items


def read_control(path):
    text = subprocess.check_output(["dpkg-deb", "-f", path], text=True)
    fields = {}
    key = None
    for line in text.splitlines():
        if line[:1] in (" ", "\t") and key:
            fields[key] += " " + line.strip()
        elif ":" in line:
            key, _, value = line.partition(":")
            key = key.strip()
            fields[key] = value.strip()
    return fields


def main():
    stanzas = []
    for release in releases():
        for asset in release.get("assets", []):
            name = asset["name"]
            if not name.endswith(".deb"):
                continue
            url = asset["browser_download_url"]
            with tempfile.NamedTemporaryFile(suffix=".deb", delete=False) as tmp:
                urllib.request.urlretrieve(url, tmp.name)
                data = open(tmp.name, "rb").read()
                control = read_control(tmp.name)
                os.unlink(tmp.name)
            lines = []
            for field in CONTROL_FIELDS:
                if field in control:
                    lines.append("%s: %s" % (field, control[field]))
            lines.append("Filename: %s" % url)
            lines.append("Size: %d" % len(data))
            lines.append("SHA256: %s" % hashlib.sha256(data).hexdigest())
            lines.append("Depiction: https://github.com/%s" % REPO)
            lines.append("Icon: %s/icon.png" % RAW)
            stanzas.append("\n".join(lines))

    if not stanzas:
        print("no release assets found; leaving docs/Packages untouched", file=sys.stderr)
        return

    body = "\n\n".join(stanzas) + "\n"
    with open("docs/Packages", "w") as handle:
        handle.write(body)
    # gzip.GzipFile takes mtime; gzip.open does not, so build it explicitly.
    with open("docs/Packages.gz", "wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as handle:
            handle.write(body.encode())
    open("docs/.nojekyll", "w").close()
    print("wrote docs/Packages (%d stanza(s))" % len(stanzas))


if __name__ == "__main__":
    main()
