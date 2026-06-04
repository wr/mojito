#!/usr/bin/env python3
"""Insert/update a version entry in the Sparkle appcast.xml on gh-pages."""

import argparse
import os
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

NS = {
    "sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle",
}
ET.register_namespace("sparkle", NS["sparkle"])

# Predefined XML namespace — ElementTree serializes this as `xml:lang` without
# an explicit xmlns declaration. Sparkle resolves the per-language node via
# +[NSBundle preferredLocalizationsFromArray:], so an untagged node counts as
# "en" and the first node in document order is the ultimate no-match fallback.
XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"


def localized_url(en_url: str, locale: str) -> str:
    """`…/release-notes/1.2.2.html` → `…/release-notes/<locale>/1.2.2.html`."""
    base, _, fname = en_url.rpartition("/")
    return f"{base}/{locale}/{fname}"


def empty_appcast() -> ET.ElementTree:
    # ET.register_namespace above emits xmlns:sparkle automatically when any
    # child uses the namespace. Setting it as an explicit attribute here too
    # produces a duplicate xmlns:sparkle on <rss>, which Sparkle's parser
    # rejects with "An error occurred while parsing the update feed".
    rss = ET.Element("rss", attrib={"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Mojito"
    ET.SubElement(channel, "link").text = "https://github.com/wr/mojito"
    ET.SubElement(channel, "description").text = "Mojito updates"
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(rss)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--appcast", required=True)
    p.add_argument("--version", required=True, help="Marketing version (CFBundleShortVersionString)")
    p.add_argument("--build", required=True, help="Build number (CFBundleVersion) — what Sparkle actually compares")
    p.add_argument("--url", required=True)
    p.add_argument("--length", required=True)
    p.add_argument("--signature", required=True)
    p.add_argument("--release-notes-url", default="", help="URL to the English HTML release notes for this version")
    p.add_argument("--full-release-notes-url", default="", help="URL to the English full version-history page (Sparkle's 'Version history' link)")
    p.add_argument("--locales", default="", help="Space-separated locales with rendered localized notes; emits xml:lang variants alongside English")
    args = p.parse_args()
    locales = [loc for loc in args.locales.split() if loc]

    if os.path.exists(args.appcast):
        tree = ET.parse(args.appcast)
    else:
        tree = empty_appcast()

    root = tree.getroot()
    channel = root.find("channel")
    if channel is None:
        return 1

    # Remove any prior entry with the same version (idempotent re-runs).
    for item in channel.findall("item"):
        version_elem = item.find("{%s}shortVersionString" % NS["sparkle"])
        if version_elem is not None and version_elem.text == args.version:
            channel.remove(item)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Mojito {args.version}"
    ET.SubElement(
        item,
        "pubDate",
    ).text = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    ET.SubElement(item, "{%s}shortVersionString" % NS["sparkle"]).text = args.version
    # sparkle:version corresponds to CFBundleVersion — Sparkle does its
    # update comparison against this field, NOT shortVersionString.
    ET.SubElement(item, "{%s}version" % NS["sparkle"]).text = args.build
    ET.SubElement(item, "{%s}minimumSystemVersion" % NS["sparkle"]).text = "14.0"
    def add_notes_link(tag: str, en_url: str) -> None:
        # The appcast element is `sparkle:releaseNotesLink` — NOT
        # `releaseNotesURL` (that's the SUAppcastItem *property* name). Sparkle
        # silently ignores the unknown element, so the wrong name leaves the
        # update dialog with a blank release-notes pane.
        if not en_url:
            return
        if not locales:
            ET.SubElement(item, "{%s}%s" % (NS["sparkle"], tag)).text = en_url
            return
        # Localized: tag English explicitly and keep it first (it's the no-match
        # fallback), then one node per locale with its `/<locale>/` URL.
        en = ET.SubElement(item, "{%s}%s" % (NS["sparkle"], tag))
        en.set(XML_LANG, "en")
        en.text = en_url
        for loc in locales:
            node = ET.SubElement(item, "{%s}%s" % (NS["sparkle"], tag))
            node.set(XML_LANG, loc)
            node.text = localized_url(en_url, loc)

    # releaseNotesLink → per-version notes; fullReleaseNotesLink → "Version
    # history" link in the update dialog.
    add_notes_link("releaseNotesLink", args.release_notes_url)
    add_notes_link("fullReleaseNotesLink", args.full_release_notes_url)
    ET.SubElement(
        item,
        "enclosure",
        attrib={
            "url": args.url,
            "type": "application/octet-stream",
            "length": str(args.length),
            "{%s}edSignature" % NS["sparkle"]: args.signature,
        },
    )

    # Insert at the top of items.
    items = channel.findall("item")
    insertion_index = list(channel).index(items[0]) if items else len(list(channel))
    channel.insert(insertion_index, item)

    ET.indent(tree, space="  ")
    tree.write(args.appcast, encoding="utf-8", xml_declaration=True)
    print(f"updated {args.appcast} with v{args.version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
