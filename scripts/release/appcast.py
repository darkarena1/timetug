#!/usr/bin/env python3
"""Edit the Sparkle appcast (appcast.xml). Stdlib only. See docs/release.md."""
import argparse
import os
import sys
import xml.etree.ElementTree as ET
from email.utils import formatdate

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")


def q(tag):
    return "{%s}%s" % (SPARKLE, tag)


def load(path):
    if os.path.exists(path):
        return ET.parse(path)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "TimeTug"
    return ET.ElementTree(rss)


def version_of(item):
    node = item.find(q("version"))
    if node is None:
        return None
    text = (node.text or "").strip()
    return int(text) if text.isdigit() else None


def is_beta(item):
    node = item.find(q("channel"))
    return node is not None and (node.text or "").strip() == "beta"


def save(tree, path):
    ET.indent(tree, space="  ")
    tree.write(path, encoding="utf-8", xml_declaration=True)


def cmd_add(a):
    if not a.version.isdigit():
        sys.exit("error: --version must be numeric")
    tree = load(a.file)
    channel = tree.getroot().find("channel")
    same = [i for i in channel.findall("item") if (i.findtext(q("version")) or "").strip() == a.version]
    for old in same:
        enc = old.find("enclosure")
        if enc is None or enc.get("url") != a.url:
            sys.exit(f"error: sparkle:version {a.version} already exists with a different enclosure url")
    same_url = [i for i in channel.findall("item")
                if i.find("enclosure") is not None and i.find("enclosure").get("url") == a.url]
    for old in {id(x): x for x in same + same_url}.values():
        channel.remove(old)
    item = ET.Element("item")
    ET.SubElement(item, "title").text = a.title
    ET.SubElement(item, "pubDate").text = formatdate(usegmt=True)
    ET.SubElement(item, q("version")).text = a.version
    ET.SubElement(item, q("shortVersionString")).text = a.short
    ET.SubElement(item, q("minimumSystemVersion")).text = a.min_system
    if a.channel:
        ET.SubElement(item, q("channel")).text = a.channel
    if a.notes_url:
        ET.SubElement(item, q("releaseNotesLink")).text = a.notes_url
    ET.SubElement(item, "enclosure", {
        "url": a.url, "length": a.length, "type": "application/octet-stream",
        q("edSignature"): a.signature,
    })
    first = next((i for i, e in enumerate(channel) if e.tag == "item"), len(channel))
    channel.insert(first, item)
    items = sorted(channel.findall("item"), key=lambda x: version_of(x) if version_of(x) is not None else -1, reverse=True)
    for i in items:
        channel.remove(i)
    for i in items:
        channel.append(i)
    save(tree, a.file)


def cmd_prune(a):
    if not os.path.exists(a.file):
        sys.exit(f"error: no appcast at {a.file}")
    tree = ET.parse(a.file)
    channel = tree.getroot().find("channel")
    betas = [i for i in channel.findall("item") if is_beta(i) and version_of(i) is not None]
    betas = sorted(betas, key=version_of, reverse=True)
    for item in betas[a.keep:]:
        enclosure = item.find("enclosure")
        if enclosure is not None and enclosure.get("url"):
            print(enclosure.get("url"))
        channel.remove(item)
    save(tree, a.file)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    add = sub.add_parser("add")
    for name in ("file", "title", "version", "short", "url", "length", "signature", "min-system"):
        add.add_argument("--" + name, required=True, dest=name.replace("-", "_"))
    add.add_argument("--channel")
    add.add_argument("--notes-url", dest="notes_url")
    add.set_defaults(fn=cmd_add)
    prune = sub.add_parser("prune-betas")
    prune.add_argument("--file", required=True)
    prune.add_argument("--keep", type=int, required=True)
    prune.set_defaults(fn=cmd_prune)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
