/**
 * Shared footer widget — injected into any page that contains
 * <footer id="footer-widget" class="site-footer"></footer>.
 * Edit this file once; all pages get the same footer.
 */
(function () {
  const footerHtml = `
    <div class="container footer-inner">
      <div class="footer-brand">
        <img src="assets/img/logo_text_white.png" alt="Croploo" class="brand-mark logo-light" />
        <img src="assets/img/logo_text_black.png" alt="Croploo" class="brand-mark logo-dark" />
        <p>The basis for better trades.</p>
      </div>
      <div class="footer-links">
        <div class="footer-col">
          <h4>Product</h4>
          <a href="index.html#features">Features</a>
          <a href="index.html#screenshots">Screenshots</a>
          <a href="index.html#markets">Markets</a>
          <a href="index.html#pricing">Pricing</a>
          <a href="index.html#download">Download</a>
        </div>
        <div class="footer-col">
          <h4>Resources</h4>
          <a href="index.html#sources">Data Sources</a>
          <a href="index.html#top">Status</a>
          <a href="index.html#top">Documentation</a>
        </div>
        <div class="footer-col">
          <h4>Company</h4>
          <a href="about.html">About</a>
          <a href="contact.html">Contact</a>
          <a href="privacy.html">Privacy</a>
        </div>
      </div>
    </div>
    <div class="container footer-bottom">
      <p>&copy; 2026 Cultioo Inc. All rights reserved.</p>
    </div>
  `;

  const el = document.getElementById('footer-widget');
  if (el) {
    el.innerHTML = footerHtml;
  } else {
    console.warn('footer.js: no element with id="footer-widget" found');
  }
})();
