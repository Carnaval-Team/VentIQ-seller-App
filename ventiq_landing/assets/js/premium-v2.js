/* =========================================================
   INVENTTIA · Premium v2 motion layer
   Lenis smooth scroll · GSAP reveals · magnetic CTAs
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
            }, { threshold: 0.18, rootMargin: '0px 0px -60px 0px' });
            revealEls.forEach(el => io.observe(el));
        }
    }

    // ---------- 3. Magnetic CTAs ----------
    if (!REDUCE) {
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
        function raf(time) {
            lenis.raf(time);
            requestAnimationFrame(raf);
        }
        requestAnimationFrame(raf);
        lenis.on('scroll', ScrollTrigger.update);

        // ---------- Sticky-stack (canonical skeleton, Section 5.A) ----------
        const cards = gsap.utils.toArray('.v2-stack-card');
        cards.forEach((card, i) => {
            if (i === cards.length - 1) return;
            ScrollTrigger.create({
                trigger: card,
                start: 'top top+=88',     // account for fixed nav (64–80px)
                endTrigger: cards[cards.length - 1],
                end: 'top top+=88',
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
})();
