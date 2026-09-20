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

    def test_rejects_non_numeric_version(self):
        r = run("add", "--file", self.path, "--title", "t", "--version", "abc", "--short", "1",
                "--url", "https://e/x.zip", "--length", "1", "--signature", "s", "--min-system", "14.0")
        self.assertNotEqual(r.returncode, 0)

if __name__ == "__main__":
    unittest.main()
