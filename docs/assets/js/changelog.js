// Renders the repository's CHANGELOG.md into the Changelog page. The file lives
// outside the Pages source, so each visit loads its current version.
(function () {
  var container = document.getElementById("changelog");
  var repo = container.dataset.repository;
  var branch = container.dataset.branch;
  var blob = "https://github.com/" + repo + "/blob/" + branch + "/";

  function fail() {
    container.innerHTML = '<p>The changelog could not be loaded. Read <a href="' + blob + 'CHANGELOG.md">CHANGELOG.md on GitHub</a>.</p>';
  }

  // GitHub heading IDs, so links such as #300---unreleased resolve.
  function slug(text, seen) {
    var base = text.trim().toLowerCase().replace(/[^\p{L}\p{M}\p{N}\p{Pc} -]/gu, "").replace(/ /g, "-");
    var count = seen[base] || 0;
    seen[base] = count + 1;
    return count ? base + "-" + count : base;
  }

  function collapseEntries() {
    container.querySelectorAll(":scope > h2").forEach(function (heading, index) {
      var entry = document.createElement("details");
      entry.className = "changelog-entry";
      entry.open = index === 0;
      var summary = document.createElement("summary");
      var content = document.createElement("div");
      content.className = "changelog-entry-content";
      container.insertBefore(entry, heading);
      entry.appendChild(summary);
      summary.appendChild(heading);
      entry.appendChild(content);
      while (entry.nextSibling && entry.nextSibling.nodeName !== "H2") {
        content.appendChild(entry.nextSibling);
      }
    });
  }

  function revealHash() {
    if (!location.hash) return;
    var id;
    try {
      id = decodeURIComponent(location.hash.slice(1));
    } catch (error) {
      return;
    }
    var target = document.getElementById(id);
    if (!target || !container.contains(target)) return;
    var entry = target.closest(".changelog-entry");
    if (entry) entry.open = true;
    target.scrollIntoView();
  }

  if (!window.marked) {
    fail();
    return;
  }

  fetch("https://raw.githubusercontent.com/" + repo + "/" + branch + "/CHANGELOG.md", { cache: "no-cache" })
    .then(function (response) {
      if (!response.ok) throw new Error("HTTP " + response.status);
      return response.text();
    })
    .then(function (markdown) {
      // Repository content, trusted like the rest of the site.
      container.innerHTML = marked.parse(markdown);
      var seen = {};
      container.querySelectorAll("h1, h2, h3, h4, h5, h6").forEach(function (heading) {
        heading.id = slug(heading.textContent, seen);
      });
      container.querySelectorAll("a[href]").forEach(function (link) {
        var href = link.getAttribute("href");
        if (!/^([a-z][a-z0-9+.-]*:|#|\/)/i.test(href)) link.href = blob + href;
      });
      collapseEntries();
      revealHash();
      window.addEventListener("hashchange", revealHash);
    })
    .catch(fail);
})();
