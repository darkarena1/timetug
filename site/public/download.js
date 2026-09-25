// Release assets have versioned names, so resolve the current stable DMG when the page loads.
const download = document.querySelector('[data-latest-dmg]');
if (download) {
  fetch('https://api.github.com/repos/darkarena1/timetug/releases/latest', {
    headers: { Accept: 'application/vnd.github+json' }
  })
    .then(response => {
      if (!response.ok) throw new Error(`GitHub release lookup failed: ${response.status}`);
      return response.json();
    })
    .then(release => {
      const dmg = release.assets?.find(asset => /^TimeTug-.*\.dmg$/.test(asset.name) && !asset.name.endsWith('-unsigned.dmg'));
      if (dmg?.browser_download_url) download.href = dmg.browser_download_url;
    })
    .catch(() => {
      // The initial link still opens GitHub's latest release if the lookup is unavailable.
    });
}
