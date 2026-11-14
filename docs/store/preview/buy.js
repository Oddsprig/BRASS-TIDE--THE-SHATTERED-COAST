// Brass Tide listing uses the same-origin marketplace API and owner-only library.
(function () {
  "use strict";
  var PRODUCT = "brass-tide";
  var buys = document.querySelectorAll('[data-buy-product="' + PRODUCT + '"]');
  if (!buys.length) return;
  var dls = document.querySelectorAll("[data-download]");
  var status = document.querySelector("[data-store-status]");
  var error = document.querySelector("[data-buy-error]");
  var retry = document.querySelector("[data-store-retry]");
  var owned = false;
  var loading = false;

  function setAllText(selector, value) {
    if (value === undefined || value === null || value === "") return;
    var els = document.querySelectorAll(selector);
    for (var i = 0; i < els.length; i++) {
      els[i].textContent = String(value);
    }
  }

  function priceText(p) {
    return typeof p.price_cents === "number" ? "$" + (p.price_cents / 100).toFixed(2) : "$9.99";
  }

  function versionFor(p, platform) {
    var versions = p.versions || p.latest || p.latest_versions || {};
    var entry = versions[platform];
    return entry && typeof entry === "object" ? entry.version : entry;
  }

  function sizeFor(p, platform) {
    var versions = p.versions || p.latest || p.latest_versions || {};
    var entry = versions[platform];
    if (entry && typeof entry === "object" && typeof entry.size_bytes === "number" && entry.size_bytes > 0) {
      return "About " + Math.max(1, Math.round(entry.size_bytes / 1e6)) + " MB (.zip).";
    }
    return null;
  }

  function setBuysState(opts) {
    for (var i = 0; i < buys.length; i++) {
      if (opts.href !== undefined) buys[i].href = opts.href;
      if (opts.text !== undefined) buys[i].textContent = opts.text;
      if (opts.disabled === true) buys[i].setAttribute("aria-disabled", "true");
      else if (opts.disabled === false) buys[i].removeAttribute("aria-disabled");
      if (opts.busy === true) buys[i].setAttribute("aria-busy", "true");
      else if (opts.busy === false) buys[i].removeAttribute("aria-busy");
    }
  }

  function request(url, options) {
    var controller = new AbortController();
    var timeout = setTimeout(function () { controller.abort(); }, 10000);
    options.signal = controller.signal;
    return fetch(url, options).then(function (response) {
      if (!response.ok) throw new Error("Store request failed: " + response.status);
      return response.json();
    }).finally(function () { clearTimeout(timeout); });
  }

  function loadStore() {
    if (loading) return;
    loading = true;
    if (error) error.hidden = true;
    if (retry) retry.hidden = true;
    if (status) { status.hidden = false; status.textContent = "Checking price and availability…"; }
    setBuysState({ disabled: true, busy: true, text: "Checking store…" });
    request("/api/products/" + PRODUCT, { credentials: "include", headers: { Accept: "application/json" } })
      .then(function (product) {
        if (!product || product.id !== PRODUCT) throw new Error("Unexpected product");
        owned = !!product.owned;
        var price = priceText(product);
        setAllText("[data-price]", price);
        var pc = versionFor(product, "windows") || versionFor(product, "pc");
        if (!pc) throw new Error("Windows release is unavailable");
        setAllText("[data-version-pc], [data-current-version]", pc);
        var sizeLabel = sizeFor(product, "windows") || sizeFor(product, "pc");
        if (sizeLabel) setAllText("[data-download-size]", sizeLabel);
        setBuysState({
          href: owned ? "/library/" : "#buy",
          text: owned ? "In your library" : "Buy — " + price,
          disabled: false
        });
        if (status) status.hidden = true;
        for (var i = 0; i < dls.length; i++) {
          dls[i].href = "/library/";
          dls[i].removeAttribute("aria-disabled");
          dls[i].textContent = owned ? "Download for Windows" : "Download from your library";
        }
      })
      .catch(function () {
        setBuysState({ text: "Store unavailable", disabled: true });
        if (status) { status.hidden = false; status.textContent = "The store could not be reached. Please retry."; }
        if (retry) retry.hidden = false;
      })
      .finally(function () {
        loading = false;
        setBuysState({ busy: false });
      });
  }

  function handleBuyClick(event) {
    var target = event.currentTarget;
    if (target.getAttribute("aria-disabled") === "true") { event.preventDefault(); return; }
    if (owned) return;
    event.preventDefault();
    if (target.getAttribute("aria-busy") === "true") return;
    var label = target.textContent;
    setBuysState({ busy: true, text: "Opening checkout…" });
    if (error) error.hidden = true;
    request("/api/checkout", {
      method: "POST", credentials: "include",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ product_id: PRODUCT })
    }).then(function (checkout) {
      if (!checkout || !checkout.url) throw new Error("Checkout URL missing");
      window.location.href = checkout.url;
    }).catch(function () {
      setBuysState({ busy: false, text: label });
      if (error) error.hidden = false;
    });
  }

  for (var i = 0; i < buys.length; i++) {
    buys[i].addEventListener("click", handleBuyClick);
  }
  for (var j = 0; j < dls.length; j++) {
    dls[j].addEventListener("click", function (event) {
      if (this.getAttribute("aria-disabled") === "true") event.preventDefault();
    });
  }
  if (retry) retry.addEventListener("click", loadStore);
  window.addEventListener("pageshow", function (event) {
    if (event.persisted) loadStore();
  });
  loadStore();
})();
