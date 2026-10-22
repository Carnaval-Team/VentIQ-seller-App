/* =========================================================
   INVENTTIA · Premium v3 motion layer
   Optional Lenis smooth scroll · CSS reveals · magnetic CTAs ·
   scroll progress · mouse spotlight · 3D phone tilt · word reveals ·
   sticky-stack depth (native scroll + rAF)
   Every effect is CDN-independent and gated by prefers-reduced-motion.
   ========================================================= */

(function () {
    const REDUCE = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    // ---------- 1. Nav stuck state ----------
    const nav = document.querySelector('.v2-nav');
    if (nav) {
        const onScroll = () => {
            if (window.scrollY > 8) nav.classList.add('is-stuck');
            else nav.classList.remove('is-stuck');
        };
        // Passive scroll listener only for the nav class swap — single boolean, no per-frame work.
        // (Position-driven anims use native scroll + IntersectionObserver below.)
        window.addEventListener('scroll', onScroll, { passive: true });
        onScroll();
    }

    // ---------- 1b. Mobile drawer ----------
    // Lenis is loaded later and captures wheel events, so the drawer parks it
    // via window.__v2Lenis (set below) instead of relying on overflow:hidden.
    const burger = document.querySelector('.v2-burger');
    const drawer = document.querySelector('[data-drawer]');
    if (burger && drawer) {
        const closeBtn = drawer.querySelector('[data-drawer-close]');
        const scrim = drawer.querySelector('.v2-drawer-scrim');

        const openDrawer = () => {
            drawer.classList.add('is-open');
            drawer.setAttribute('aria-hidden', 'false');
            document.body.classList.add('v2-no-scroll');
            burger.setAttribute('aria-expanded', 'true');
            if (window.__v2Lenis) window.__v2Lenis.stop();
            const first = drawer.querySelector('a, button');
            if (first) first.focus();
        };

        const closeDrawer = () => {
            drawer.classList.remove('is-open');
            drawer.setAttribute('aria-hidden', 'true');
            document.body.classList.remove('v2-no-scroll');
            burger.setAttribute('aria-expanded', 'false');
            if (window.__v2Lenis) window.__v2Lenis.start();
        };

        burger.addEventListener('click', openDrawer);
        if (closeBtn) closeBtn.addEventListener('click', closeDrawer);
        if (scrim) scrim.addEventListener('click', closeDrawer);
        drawer.querySelectorAll('a').forEach((a) => a.addEventListener('click', closeDrawer));
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && drawer.classList.contains('is-open')) closeDrawer();
        });
    }

    // ---------- 2. CSS-driven reveal fallback (always on, no JS deps) ----------
    const revealEls = document.querySelectorAll('.v2-reveal');
    if (revealEls.length) {
        if (REDUCE) {
            revealEls.forEach(el => el.classList.add('is-in'));
        } else {
            const io = new IntersectionObserver((entries) => {
                entries.forEach((e) => {
                    if (e.isIntersecting) {
                        e.target.classList.add('is-in');
                        io.unobserve(e.target);
                    }
                });
            }, {
                threshold: window.matchMedia('(max-width: 540px)').matches ? 0.08 : 0.14,
                rootMargin: window.matchMedia('(max-width: 540px)').matches ? '0px 0px -24px 0px' : '0px 0px -48px 0px',
            });
            revealEls.forEach(el => io.observe(el));
        }
    }

    // ---------- 2b. Scroll progress bar ----------
    const progressBar = document.querySelector('.v2-scroll-progress');
    if (progressBar) {
        const updateProgress = () => {
            const h = document.documentElement;
            const total = h.scrollHeight - h.clientHeight;
            const pct = total > 0 ? (h.scrollTop / total) * 100 : 0;
            progressBar.style.width = `${Math.min(pct, 100)}%`;
        };
        window.addEventListener('scroll', updateProgress, { passive: true });
        updateProgress();
    }

    // ---------- 2c. Hero word reveal ----------
    const heroHeadline = document.querySelector('.v2-hero h1');
    if (heroHeadline && !REDUCE) {
        splitTextIntoWords(heroHeadline);
        requestAnimationFrame(() => heroHeadline.classList.add('is-revealed'));
        // Release the per-word overflow clip once the reveal has settled, otherwise
        // descenders/overhang of words like "que" or "y" stay chopped. Not tied to
        // any CDN: this always runs, whatever happens with the optional script loads.
        window.setTimeout(() => heroHeadline.classList.add('is-revealed-settled'), 1400);
    }

    // ---------- 3. Magnetic CTAs (mouse only) ----------
    if (!REDUCE && window.matchMedia('(pointer: fine)').matches) {
        const magnets = document.querySelectorAll('[data-magnetic]');
        magnets.forEach((el) => {
            const strength = parseFloat(el.dataset.magnetic || '0.28');
            let raf = null;
            let tx = 0, ty = 0, cx = 0, cy = 0;

            const onMove = (e) => {
                const r = el.getBoundingClientRect();
                tx = (e.clientX - (r.left + r.width / 2)) * strength;
                ty = (e.clientY - (r.top + r.height / 2)) * strength;
                if (!raf) raf = requestAnimationFrame(tick);
            };
            const onLeave = () => {
                tx = 0; ty = 0;
                if (!raf) raf = requestAnimationFrame(tick);
            };
            const tick = () => {
                cx += (tx - cx) * 0.18;
                cy += (ty - cy) * 0.18;
                if (Math.abs(tx - cx) <= 0.1 && Math.abs(ty - cy) <= 0.1) {
                    raf = null;
                    if (tx === 0 && ty === 0) {
                        // At rest with the pointer away: drop the inline transform so the
                        // CSS :hover lift (translateY(-2px)) is not permanently overridden.
                        cx = 0;
                        cy = 0;
                        el.style.transform = '';
                    } else {
                        el.style.transform = `translate3d(${cx.toFixed(2)}px, ${cy.toFixed(2)}px, 0)`;
                    }
                    return;
                }
                el.style.transform = `translate3d(${cx.toFixed(2)}px, ${cy.toFixed(2)}px, 0)`;
                raf = requestAnimationFrame(tick);
            };
            el.addEventListener('pointermove', onMove);
            el.addEventListener('pointerleave', onLeave);
        });
    }

    // ---------- 3b. Mouse spotlight + 3D phone tilt (mouse only) ----------
    if (!REDUCE && window.matchMedia('(pointer: fine)').matches) {
        initSpotlight();
        initPhoneTilt();
    }

    // ---------- 4. Sticky-stack depth (vanilla: native scroll + one rAF loop) ----------
    // CSS `position: sticky` does all the pinning; this only writes --stack-progress so
    // each card eases back as the next one arrives. Works with or without Lenis, because
    // Lenis drives native scroll and nothing here waits on a CDN.
    if (REDUCE) return;

    const stackCards = Array.from(document.querySelectorAll('.v2-stack-card'));
    const stackSection = document.querySelector('.v2-stack');
    // Exact complement of the CSS un-stick breakpoints (max-width: 880px / max-height: 720px).
    const stackSticky = window.matchMedia('(min-width: 881px) and (min-height: 721px)');
    if (stackCards.length > 1) {
        const NAV_OFFSET = 88;
        let stackTops = [];
        let stackRaf = null;
        let stackNeedsMeasure = true;
        const lastProgress = [];

        // Only touch the DOM when the value actually changes (keeps mobile scrolling cheap).
        const setProgress = (card, i, value) => {
            const text = value.toFixed(3);
            if (lastProgress[i] === text) return;
            lastProgress[i] = text;
            card.style.setProperty('--stack-progress', text);
        };

        // Natural (document-space) tops of the cards, derived from LAYOUT ONLY:
        //   anchor = the non-sticky intro's layout top + its height + its margin
        //   then each card = previous top + its own layout height + its margin
        // offsetTop of non-sticky boxes, offsetHeight and computed margins are all
        // scroll-invariant — sticky offsets and transforms never leak into them.
        // NEVER use getBoundingClientRect() here: on a stuck card the rect tracks the
        // scroll position, which makes (scrollY + 88 - cardTop) constant and freezes
        // --stack-progress in place. The loop below is pure arithmetic on these tops.
        const chainTop = (el) => {
            let top = 0;
            let node = el;
            while (node) {
                top += node.offsetTop || 0;
                node = node.offsetParent;
            }
            return top;
        };
        const bottomMargin = (el) => parseFloat(window.getComputedStyle(el).marginBottom) || 0;

        const measureStack = () => {
            const first = stackCards[0];
            const intro = (stackSection && stackSection.querySelector('.v2-stack-intro')) ||
                          first.previousElementSibling;
            let top = intro
                ? chainTop(intro) + intro.offsetHeight + bottomMargin(intro)
                : chainTop(first);
            stackTops = stackCards.map((card) => {
                const here = top;
                top += card.offsetHeight + bottomMargin(card);
                return here;
            });
            lastProgress.length = 0;
        };

        const updateStack = () => {
            stackRaf = null;
            if (stackNeedsMeasure) {
                measureStack();
                stackNeedsMeasure = false;
            }
            if (!stackSticky.matches) {
                stackCards.forEach((card, i) => setProgress(card, i, 0));
                return;
            }
            const scrollTop = window.scrollY || document.documentElement.scrollTop || 0;
            for (let i = 0; i < stackCards.length - 1; i += 1) {
                const from = stackTops[i];
                const to = stackTops[i + 1];
                const span = to - from;
                const raw = span > 0 ? (scrollTop + NAV_OFFSET - from) / span : 0;
                setProgress(stackCards[i], i, Math.min(1, Math.max(0, raw)));
            }
            // The last card has nothing to recede behind: keep it fully visible.
            setProgress(stackCards[stackCards.length - 1], stackCards.length - 1, 0);
        };

        const queueStackUpdate = () => {
            if (stackRaf === null) stackRaf = requestAnimationFrame(updateStack);
        };
        const refreshStack = () => {
            stackNeedsMeasure = true;
            queueStackUpdate();
        };

        window.addEventListener('scroll', queueStackUpdate, { passive: true });
        window.addEventListener('resize', refreshStack);
        window.addEventListener('load', refreshStack);
        if (document.fonts && document.fonts.ready) {
            document.fonts.ready.then(refreshStack).catch(() => {});
        }
        if (stackSection && 'ResizeObserver' in window) {
            new ResizeObserver(refreshStack).observe(stackSection);
        }
        refreshStack();
    }

    // ---------- 5. Lenis smooth scroll (optional enhancement, never required) ----------
    // Fire-and-forget. Nothing above depends on it: if the CDN is blocked, slow or
    // missing, scrolling and every animation still work, because they are driven by
    // native scroll, IntersectionObserver and CSS only.
    loadScript('https://cdn.jsdelivr.net/npm/lenis@1.0.43/dist/lenis.min.js')
        .then(() => {
            const { Lenis } = window;
            if (typeof Lenis !== 'function') {
                console.warn('[premium-v3] Lenis loaded but not constructable — skipping');
                return;
            }
            const lenis = new Lenis({
                duration: 1.1,
                easing: (t) => 1 - Math.pow(1 - t, 3),
                smoothWheel: true,
                smoothTouch: false,
            });
            // Exposed so the drawer can pause smooth scroll while it's open.
            window.__v2Lenis = lenis;
            const raf = (time) => {
                lenis.raf(time);
                requestAnimationFrame(raf);
            };
            requestAnimationFrame(raf);
        })
        .catch((err) => console.warn('[premium-v3] smooth scroll unavailable', err));

    // ---------- helpers ----------
    function loadScript(src) {
        return new Promise((resolve, reject) => {
            const existing = document.querySelector(`script[src="${src}"]`);
            if (existing) { existing.addEventListener('load', resolve); return; }
            const s = document.createElement('script');
            s.src = src;
            s.async = true;
            s.onload = resolve;
            s.onerror = reject;
            document.head.appendChild(s);
        });
    }

    function splitTextIntoWords(el) {
        const children = Array.from(el.childNodes);
        el.innerHTML = '';
        children.forEach((node) => {
            if (node.nodeType === Node.TEXT_NODE) {
                node.textContent.split(/(\s+)/).forEach((piece) => {
                    if (!piece.trim()) {
                        el.appendChild(document.createTextNode(piece));
                        return;
                    }
                    const span = document.createElement('span');
                    span.className = 'word';
                    const inner = document.createElement('span');
                    inner.className = 'word-inner';
                    inner.textContent = piece;
                    span.appendChild(inner);
                    el.appendChild(span);
                });
            } else if (node.nodeType === Node.ELEMENT_NODE) {
                const clone = node.cloneNode(true);
                el.appendChild(clone);
            }
        });
    }

    function initSpotlight() {
        const selectors = '.v2-stack-card, .v2-tile, .v2-carnaval, .v2-flow';
        document.querySelectorAll(selectors).forEach((card) => {
            const onMove = (e) => {
                const rect = card.getBoundingClientRect();
                const x = ((e.clientX - rect.left) / rect.width) * 100;
                const y = ((e.clientY - rect.top) / rect.height) * 100;
                card.style.setProperty('--mouse-x', `${x}%`);
                card.style.setProperty('--mouse-y', `${y}%`);
            };
            card.addEventListener('pointermove', onMove);
        });
    }

    function initPhoneTilt() {
        document.querySelectorAll('.v2-phone').forEach((phone) => {
            phone.setAttribute('data-tilt', '');
            const parent = phone.closest('.v2-hero-visual, .v2-stack-visual, .v2-carnaval-visual-phone, .v2-flow-visual');
            if (!parent) return;
            parent.style.perspective = '1200px';

            let raf = null;
            let rx = 0, ry = 0, cx = 0, cy = 0;
            const onMove = (e) => {
                const rect = parent.getBoundingClientRect();
                const x = (e.clientX - rect.left) / rect.width - 0.5;
                const y = (e.clientY - rect.top) / rect.height - 0.5;
                ry = x * 12;   // rotateY
                rx = -y * 12;  // rotateX
                if (!raf) raf = requestAnimationFrame(tick);
            };
            const onLeave = () => { rx = 0; ry = 0; if (!raf) raf = requestAnimationFrame(tick); };
            const tick = () => {
                cx += (rx - cx) * 0.12;
                cy += (ry - cy) * 0.12;
                phone.style.transform = `rotateX(${cy.toFixed(2)}deg) rotateY(${cx.toFixed(2)}deg)`;
                if (Math.abs(rx - cx) > 0.05 || Math.abs(ry - cy) > 0.05) {
                    raf = requestAnimationFrame(tick);
                } else {
                    raf = null;
                }
            };
            parent.addEventListener('pointermove', onMove);
            parent.addEventListener('pointerleave', onLeave);
        });
    }
})();
