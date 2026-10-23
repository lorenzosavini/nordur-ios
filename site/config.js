// Where the site's API is: api/index.php next to this file (PHP + MySQL on the
// same hosting). Sign-ups, launch status and the admin panel talk to it.
window.NORDUR_API = new URL("api/index.php", document.currentScript.src).href;
