/* =========================================================
   INVENTTIA · Premium v3 motion layer
   Lenis smooth scroll · GSAP reveals · magnetic CTAs ·
   scroll progress · mouse spotlight · 3D phone tilt · word reveals
   All gated by prefers-reduced-motion.
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
        // (Position-driven anims use ScrollTrigger / IntersectionObserver below.)
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
                el.style.transform = `translate3d(${cx.toFixed(2)}px, ${cy.toFixed(2)}px, 0)`;
                if (Math.abs(tx - cx) > 0.1 || Math.abs(ty - cy) > 0.1) {
                    raf = requestAnimationFrame(tick);
                } else {
                    raf = null;
                }
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

    // ---------- 4. Lenis + GSAP (lazy-load, only if !reduced) ----------
    if (REDUCE) return;

    Promise.all([
        loadScript('https://cdn.jsdelivr.net/npm/lenis@1.0.43/dist/lenis.min.js'),
        loadScript('https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/gsap.min.js'),
        loadScript('https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/ScrollTrigger.min.js'),
    ]).then(() => {
        const { Lenis } = window;
        const gsap = window.gsap;
        const ScrollTrigger = window.ScrollTrigger;
        gsap.registerPlugin(ScrollTrigger);

        // Lenis smooth scroll
        const lenis = new Lenis({
            duration: 1.1,
            easing: (t) => 1 - Math.pow(1 - t, 3),
            smoothWheel: true,
            smoothTouch: false,
        });
        // Exposed so the drawer can pause smooth scroll while it's open.
        window.__v2Lenis = lenis;
        function raf(time) {
            lenis.raf(time);
            requestAnimationFrame(raf);
        }
        requestAnimationFrame(raf);
        lenis.on('scroll', ScrollTrigger.update);

        // ---------- Sticky-stack (canonical skeleton, Section 5.A) ----------
        // Skip on small/short screens: CSS already stacks cards vertically and pinning
        // fights the natural document flow on phones/tablets or short desktop viewports.
        const cards = gsap.utils.toArray('.v2-stack-card');
        const enableStickyStack = !window.matchMedia('(max-width: 880px)').matches &&
                                  !window.matchMedia('(max-height: 720px)').matches;
        if (enableStickyStack) cards.forEach((card, i) => {
            if (i === cards.length - 1) return;
            ScrollTrigger.create({
                trigger: card,
                start: 'top top+=120',    // give more breathing room below the nav
                end: '+=130%',            // longer pin duration so users can read before the next card overlaps
                pin: true,
                pinSpacing: false,
            });
            gsap.to(card, {
                scale: 0.94,
                opacity: 0.55,
                y: -20,
                ease: 'none',
                scrollTrigger: {
                    trigger: cards[i + 1],
                    start: 'top bottom',
                    end: 'top top+=88',
                    scrub: true,
                },
            });
        });

        // ---------- Hero entrance (once) ----------
        const heroBits = document.querySelectorAll('[data-hero-in]');
        if (heroBits.length) {
            gsap.fromTo(
                heroBits,
                { y: 32, opacity: 0 },
                {
                    y: 0,
                    opacity: 1,
                    duration: 0.9,
                    ease: 'power3.out',
                    stagger: 0.08,
                    delay: 0.05,
                }
            );
        }

        // ---------- Bento tile stagger ----------
        const tiles = gsap.utils.toArray('.v2-tile');
        if (tiles.length) {
            gsap.from(tiles, {
                y: 36,
                opacity: 0,
                duration: 0.8,
                ease: 'power3.out',
                stagger: 0.06,
                scrollTrigger: {
                    trigger: tiles[0].parentNode,
                    start: 'top 80%',
                },
            });
        }

        // Refresh ScrollTrigger when images / fonts settle
        window.addEventListener('load', () => ScrollTrigger.refresh());
    }).catch((err) => console.warn('[premium-v2] motion bundle failed', err));

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
