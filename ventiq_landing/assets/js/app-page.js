/* =========================================================
   INVENTTIA · app-page.js
   Comportamiento propio de las páginas de app y descargas:
     · barra de descarga fija en móvil
     · acordeón de FAQ con una sola respuesta abierta
   Todo es opcional: sin JS la página sigue siendo usable.
   ========================================================= */

(function () {
  'use strict';

  // ---------- 1. Barra de descarga fija (solo móvil) ----------
  var bar = document.querySelector('[data-dl-sticky]');

  if (bar) {
    var visible = false;
    var ticking = false;

    var apply = function () {
      ticking = false;
      var y = window.scrollY || document.documentElement.scrollTop || 0;
      var shouldShow = y > 560;
      if (shouldShow === visible) return;
      visible = shouldShow;
      bar.classList.toggle('is-visible', visible);
      bar.setAttribute('aria-hidden', visible ? 'false' : 'true');
    };

    var onScroll = function () {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(apply);
    };

    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll, { passive: true });
    apply();
  }

  // ---------- 2. FAQ: una respuesta abierta a la vez ----------
  var items = Array.prototype.slice.call(document.querySelectorAll('.faq details'));

  if (items.length > 1) {
    items.forEach(function (item) {
      item.addEventListener('toggle', function () {
        if (!item.open) return;
        items.forEach(function (other) {
          if (other !== item) other.open = false;
        });
      });
    });
  }
})();