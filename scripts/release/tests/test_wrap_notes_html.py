import os, subprocess, sys, unittest

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "wrap-notes-html.py")


def run(stdin_text):
    return subprocess.run([sys.executable, SCRIPT], input=stdin_text, capture_output=True, text=True)


class WrapNotesHtmlTests(unittest.TestCase):
    def test_passes_through_input_html(self):
        r = run("<p>Fixed a bug.</p>")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("<p>Fixed a bug.</p>", r.stdout)

    def test_wraps_in_standalone_document_with_style(self):
        r = run("<p>Notes</p>")
        self.assertIn("<html>", r.stdout)
        self.assertIn("<style>", r.stdout)
        self.assertIn("prefers-color-scheme", r.stdout)

    def test_empty_input_falls_back_to_placeholder(self):
        r = run("")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("No release notes were provided", r.stdout)

    def test_whitespace_only_input_falls_back_to_placeholder(self):
        r = run("   \n  \n")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("No release notes were provided", r.stdout)


if __name__ == "__main__":
    unittest.main()
