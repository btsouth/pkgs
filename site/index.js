const page = `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>btsouth packages</title>
<style>
  body { font: 16px/1.6 system-ui, sans-serif; max-width: 40rem; margin: 4rem auto; padding: 0 1.25rem; color: #e6e6e6; background: #111; }
  a { color: #8ab4ff; }
  pre { background: #1c1c1c; padding: 1rem; border-radius: 6px; overflow-x: auto; }
</style>
<h1>btsouth packages</h1>
<p>A signed pacman repository for my Omarchy and Arch apps. Add it once and
they update with the rest of your system.</p>
<pre>curl -fsSL https://pkgs.btso.dev/install.sh | bash -s -- omaframe</pre>
<p>Swap <code>omaframe</code> for <code>omaroll</code>, <code>omakade</code> or
<code>omadrop</code>. The package list, manual steps and signing key are on
<a href="https://github.com/btsouth/pkgs">GitHub</a>.</p>
</html>
`;

export default {
  fetch() {
    return new Response(page, {
      headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=300" },
    });
  },
};
