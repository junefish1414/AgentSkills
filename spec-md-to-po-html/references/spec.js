/* ===========================================================
   spec.html / index.html 共用腳本
   產出 HTML 時把整段內聯到 <script> 標籤裡
   配合 Mermaid CDN 一起載入
   =========================================================== */

(function() {
  /* ---------- Mermaid 渲染(若頁面含 .mermaid 區塊) ---------- */
  const hasMermaid = document.querySelector('.mermaid');
  if (hasMermaid) {
    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js';
    script.onload = function() {
      const isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
      window.mermaid.initialize({
        startOnLoad: true,
        theme: isDark ? 'dark' : 'default',
        fontFamily: '-apple-system, BlinkMacSystemFont, "PingFang TC", "Noto Sans TC", sans-serif'
      });
    };
    document.head.appendChild(script);
  }

  /* ---------- 側邊目錄高亮(IntersectionObserver) ---------- */
  const links = document.querySelectorAll('.sidebar a[href^="#"]');
  if (links.length) {
    const idToLink = {};
    links.forEach(function(a) {
      const id = a.getAttribute('href').slice(1);
      idToLink[id] = a;
    });

    const headings = Object.keys(idToLink)
      .map(function(id) { return document.getElementById(id); })
      .filter(Boolean);

    if ('IntersectionObserver' in window && headings.length) {
      const observer = new IntersectionObserver(function(entries) {
        entries.forEach(function(entry) {
          if (entry.isIntersecting) {
            links.forEach(function(a) { a.classList.remove('active'); });
            const link = idToLink[entry.target.id];
            if (link) link.classList.add('active');
          }
        });
      }, { rootMargin: '-20% 0px -70% 0px' });

      headings.forEach(function(h) { observer.observe(h); });
    }
  }
})();
