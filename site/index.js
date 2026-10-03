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
<p>Swap <code>omaframe</code> for <code>omaroll</code> or <code>omadrop</code>.
Already installed from a release download? Run the command once to add repository updates.</p>
<p>For Omakade on Omarchy, select this repository explicitly:</p>
<pre>curl -fsSL https://pkgs.btso.dev/install.sh | bash
sudo pacman -S btsouth/omakade</pre>
<p>Omarchy's repository takes priority during normal updates. To update Omakade
from this repository, use <code>sudo pacman -Syu btsouth/omakade</code>.</p>
<p>The package list, manual steps and signing key are on
<a href="https://github.com/btsouth/pkgs">GitHub</a>.</p>
</html>
`;

export default {
  fetch(request) {
    // Plain HTTP is never served: a command copied without its https://
    // prefix must not fetch the installer over an unprotected connection.
    const url = new URL(request.url);
    if (url.protocol === "http:") {
      url.protocol = "https:";
      return Response.redirect(url.toString(), 301);
    }
    return new Response(page, {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "public, max-age=300",
        "strict-transport-security": "max-age=31536000",
        "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        "x-content-type-options": "nosniff",
        "referrer-policy": "no-referrer",
      },
    });
  },
};
