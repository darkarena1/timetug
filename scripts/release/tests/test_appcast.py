import os, subprocess, sys, tempfile, unittest
import xml.etree.ElementTree as ET

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "appcast.py")
NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}

def run(*args):
    return subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)

def add(path, version, channel=None, short=None):
    args = ["add", "--file", path, "--title", f"TimeTug {version}", "--version", str(version),
            "--short", short or f"0.2.0-{version}", "--url", f"https://example.com/{version}.zip",
            "--length", "100", "--signature", "SIG==", "--min-system", "14.0"]
    if channel:
        args += ["--channel", channel]
    r = run(*args)
    assert r.returncode == 0, r.stderr

def items(path):
    return ET.parse(path).getroot().findall("./channel/item")

def version(item):
    return item.find("sparkle:version", NS).text

class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.path = os.path.join(self.dir, "appcast.xml")

    def test_add_creates_file_with_one_item(self):
        add(self.path, 202609191430)
        it = items(self.path)
        self.assertEqual(len(it), 1)
        self.assertEqual(version(it[0]), "202609191430")
        enc = it[0].find("enclosure")
        self.assertEqual(enc.get("url"), "https://example.com/202609191430.zip")
        self.assertEqual(enc.get("length"), "100")
        self.assertEqual(enc.get("{%s}edSignature" % NS["sparkle"]), "SIG==")
        self.assertEqual(it[0].find("sparkle:minimumSystemVersion", NS).text, "14.0")

    def test_stable_has_no_channel_and_beta_has(self):
        add(self.path, 1, channel="beta")
        add(self.path, 2)
        by_version = {version(i): i for i in items(self.path)}
        self.assertEqual(by_version["1"].find("sparkle:channel", NS).text, "beta")
        self.assertIsNone(by_version["2"].find("sparkle:channel", NS))

    def test_newest_first_and_same_version_replaces(self):
        add(self.path, 5)
        add(self.path, 9)
        add(self.path, 9)
        self.assertEqual([version(i) for i in items(self.path)], ["9", "5"])

    def test_prune_keeps_newest_betas_and_all_stable(self):
        for v in (1, 2, 3, 4):
            add(self.path, v, channel="beta")
        add(self.path, 0)  # stable, oldest
        r = run("prune-betas", "--file", self.path, "--keep", "2")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sorted(r.stdout.split()), ["https://example.com/1.zip", "https://example.com/2.zip"])
        self.assertEqual(sorted(version(i) for i in items(self.path)), ["0", "3", "4"])

    def test_prune_compares_versions_numerically(self):
        add(self.path, 999999999999, channel="beta")
        add(self.path, 1000000000000, channel="beta")
        run("prune-betas", "--file", self.path, "--keep", "1")
        self.assertEqual([version(i) for i in items(self.path)], ["1000000000000"])

    def test_prune_orders_14_digit_second_versions_above_12_digit_minute_versions(self):
        add(self.path, 202609191430, channel="beta")      # legacy minute resolution
        add(self.path, 20260919143005, channel="beta")
        add(self.path, 20260919143001, channel="beta")
        r = run("prune-betas", "--file", self.path, "--keep", "1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual([version(i) for i in items(self.path)], ["20260919143005"])

    def test_rejects_non_numeric_version(self):
        r = run("add", "--file", self.path, "--title", "t", "--version", "abc", "--short", "1",
                "--url", "https://e/x.zip", "--length", "1", "--signature", "s", "--min-system", "14.0")
        self.assertNotEqual(r.returncode, 0)

    def test_prune_exits_nonzero_when_file_missing(self):
        r = run("prune-betas", "--file", self.path, "--keep", "1")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("error: no appcast at", r.stderr)
        self.assertFalse(os.path.exists(self.path))

    def test_add_handles_empty_version_tag(self):
        add(self.path, 1, channel="beta")
        # Manually add an item with empty version tag
        tree = ET.parse(self.path)
        channel = tree.getroot().find("channel")
        item = ET.Element("item")
        ET.SubElement(item, "title").text = "Empty Version"
        ET.SubElement(item, "{%s}version" % NS["sparkle"]).text = ""
        ET.SubElement(item, "{%s}channel" % NS["sparkle"]).text = "beta"
        ET.SubElement(item, "enclosure", {"url": "https://example.com/empty.zip"})
        channel.append(item)
        tree.write(self.path, encoding="utf-8", xml_declaration=True)

        # Adding another item should not crash
        add(self.path, 2)
        it = items(self.path)
        self.assertEqual(len(it), 3)

    def test_prune_skips_items_with_empty_version(self):
        add(self.path, 1, channel="beta")
        add(self.path, 2, channel="beta")
        # Manually add an item with empty version tag
        tree = ET.parse(self.path)
        channel = tree.getroot().find("channel")
        item = ET.Element("item")
        ET.SubElement(item, "title").text = "Empty Version"
        ET.SubElement(item, "{%s}version" % NS["sparkle"]).text = ""
        ET.SubElement(item, "{%s}channel" % NS["sparkle"]).text = "beta"
        ET.SubElement(item, "enclosure", {"url": "https://example.com/empty.zip"})
        channel.append(item)
        tree.write(self.path, encoding="utf-8", xml_declaration=True)

        r = run("prune-betas", "--file", self.path, "--keep", "1")
        self.assertEqual(r.returncode, 0, r.stderr)
        # Should keep version 2 and the empty version, prune version 1
        it = items(self.path)
        self.assertEqual(len(it), 2)
        versions = [version(i) if version(i) else "" for i in it]
        self.assertIn("2", versions)
        self.assertIn("", versions)

    def test_add_handles_whitespace_padded_version(self):
        # Manually create a file with whitespace-padded version
        tree = ET.ElementTree(ET.Element("rss", {"version": "2.0"}))
        channel = ET.SubElement(tree.getroot(), "channel")
        ET.SubElement(channel, "title").text = "TimeTug"
        item = ET.Element("item")
        ET.SubElement(item, "title").text = "Padded Version"
        ET.SubElement(item, "{%s}version" % NS["sparkle"]).text = " 202609191430 "
        ET.SubElement(item, "{%s}channel" % NS["sparkle"]).text = "beta"
        ET.SubElement(item, "enclosure", {"url": "https://example.com/padded.zip"})
        channel.append(item)
        tree.write(self.path, encoding="utf-8", xml_declaration=True)

        # Add a new item
        add(self.path, 202609191431)
        it = items(self.path)
        versions = [version(i) for i in it]
        # Should parse whitespace-padded version correctly
        self.assertIn("202609191431", versions)
        self.assertIn(" 202609191430 ", versions)

    def test_add_rejects_same_version_with_different_url(self):
        add(self.path, 7, channel="beta")
        r = run("add", "--file", self.path, "--title", "t", "--version", "7", "--short", "1",
                "--url", "https://example.com/other.zip", "--length", "1", "--signature", "S==",
                "--min-system", "14.0")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("error: sparkle:version 7 already exists with a different enclosure url", r.stderr)
        self.assertEqual([version(i) for i in items(self.path)], ["7"])
        self.assertEqual(items(self.path)[0].find("enclosure").get("url"), "https://example.com/7.zip")

    def test_add_same_version_same_url_replaces(self):
        add(self.path, 7, channel="beta", short="a")
        add(self.path, 7, channel="beta", short="b")
        it = items(self.path)
        self.assertEqual(len(it), 1)
        self.assertEqual(it[0].find("sparkle:shortVersionString", NS).text, "b")

    def _add_url(self, version, url, sig, channel=None):
        args = ["add", "--file", self.path, "--title", "t", "--version", str(version), "--short", "1",
                "--url", url, "--length", "1", "--signature", sig, "--min-system", "14.0"]
        if channel:
            args += ["--channel", channel]
        return run(*args)

    def test_add_same_url_different_version_replaces(self):
        u = "https://example.com/TimeTug-1.2.3.zip"
        self.assertEqual(self._add_url(20260919143005, u, "OLD==").returncode, 0)
        self.assertEqual(self._add_url(20260919150000, u, "NEW==").returncode, 0)
        it = items(self.path)
        self.assertEqual(len(it), 1)
        self.assertEqual(version(it[0]), "20260919150000")
        self.assertEqual(it[0].find("enclosure").get("{%s}edSignature" % NS["sparkle"]), "NEW==")

    def test_add_same_version_different_url_still_errors(self):
        self.assertEqual(self._add_url(5, "https://example.com/a.zip", "A==").returncode, 0)
        r = self._add_url(5, "https://example.com/b.zip", "B==")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(len(items(self.path)), 1)

    def test_add_orders_14_digit_stable_above_12_digit_beta(self):
        add(self.path, 202609191430, channel="beta")
        add(self.path, 20260919143005)
        self.assertEqual([version(i) for i in items(self.path)], ["20260919143005", "202609191430"])

    def test_add_later_stable_sorts_above_earlier_betas(self):
        add(self.path, 20260919143001, channel="beta")
        add(self.path, 20260919143002, channel="beta")
        add(self.path, 20260919143003)
        self.assertEqual([version(i) for i in items(self.path)],
                         ["20260919143003", "20260919143002", "20260919143001"])

    def _append_raw(self, version_text, channel_text, enclosure=True):
        tree = ET.parse(self.path)
        channel = tree.getroot().find("channel")
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, "{%s}version" % NS["sparkle"]).text = version_text
        ET.SubElement(item, "{%s}channel" % NS["sparkle"]).text = channel_text
        if enclosure:
            ET.SubElement(item, "enclosure", {"url": "https://example.com/raw.zip"})
        tree.write(self.path, encoding="utf-8", xml_declaration=True)

    def test_prune_treats_whitespace_padded_beta_as_beta(self):
        add(self.path, 3, channel="beta")
        self._append_raw("1", "\n  beta\n ")
        r = run("prune-betas", "--file", self.path, "--keep", "1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.split(), ["https://example.com/raw.zip"])
        self.assertEqual([version(i) for i in items(self.path)], ["3"])

    def test_prune_handles_beta_item_without_enclosure(self):
        add(self.path, 3, channel="beta")
        self._append_raw("1", "beta", enclosure=False)
        r = run("prune-betas", "--file", self.path, "--keep", "1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.split(), [])
        self.assertEqual([version(i) for i in items(self.path)], ["3"])

if __name__ == "__main__":
    unittest.main()
