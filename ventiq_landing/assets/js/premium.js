/* =========================================================
   INVENTTIA — Premium Interactions
   - Scroll reveal (IntersectionObserver)
   - Magnetic / radial-glow buttons
   - Animated stat counters
   - Subtle tilt on app cards
   - Auto-decorate sections with [data-reveal] hooks
   ========================================================= */
(function () {
    'use strict';

    const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    // ---------- 1. Auto-decorate the existing markup ----------
    // We mark elements with data-reveal so we don't need to edit each HTML.
    const decorate = () => {
        const map = [
            ['.section-header', 'up'],
            ['.app-card', 'up'],
            ['.benefit-card', 'up'],
            ['.feature-item', 'up'],
            // hero-image already has CSS keyframe entry; don't double-animate
            ['.cta-content', 'up'],
            ['.tutorial-card', 'up'],
            ['.video-card', 'up'],
            ['.faq-item', 'up'],
            ['.contact-card', 'up'],
            ['.footer-section', 'up'],
        ];
        map.forEach(([sel, dir]) => {
            document.querySelectorAll(sel).forEach((el) => {
                if (!el.hasAttribute('data-reveal')) el.setAttribute('data-reveal', dir);
            });
        });

        // Stagger containers
        ['.apps-showcase', '.benefits-grid', '.carnaval-features-grid', '.hero-stats'].forEach((sel) => {
            document.querySelectorAll(sel).forEach((el) => {
                if (!el.hasAttribute('data-reveal-stagger')) el.setAttribute('data-reveal-stagger', '');
            });
        });
    };

    // ---------- 2. IntersectionObserver reveal ----------
    const initReveal = () => {
        if (prefersReducedMotion) {
            document.querySelectorAll('[data-reveal], [data-reveal-stagger]').forEach((el) => el.classList.add('is-visible'));
            return;
        }
        const io = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('is-visible');
                    io.unobserve(entry.target);
                }
            });
        }, { threshold: 0.12, rootMargin: '0px 0px -60px 0px' });

        document.querySelectorAll('[data-reveal], [data-reveal-stagger]').forEach((el) => io.observe(el));
    };

    // ---------- 3. Magnetic glow on buttons ----------
    const initMagnetic = () => {
        if (prefersReducedMotion) return;
        const targets = document.querySelectorAll('.btn, .download-btn, .download-app-btn');
        targets.forEach((btn) => {
            btn.addEventListener('mousemove', (e) => {
                const r = btn.getBoundingClientRect();
                const x = ((e.clientX - r.left) / r.width) * 100;
                const y = ((e.clientY - r.top) / r.height) * 100;
                btn.style.setProperty('--x', x + '%');
                btn.style.setProperty('--y', y + '%');
            });
            btn.addEventListener('mouseleave', () => {
                btn.style.setProperty('--x', '50%');
                btn.style.setProperty('--y', '50%');
            });
        });
    };

    // ---------- 4. Spotlight glow that follows cursor on cards ----------
    // Modern minimalist: light beam tracks the mouse, no 3D distortion.
    const initSpotlight = () => {
        if (prefersReducedMotion) return;
        const cards = document.querySelectorAll('.app-card, .benefit-card, .tutorial-card, .category-card, .faq-item, .info-card, .contact-form-container');
        cards.forEach((card) => {
            card.addEventListener('mousemove', (e) => {
                const r = card.getBoundingClientRect();
                const x = ((e.clientX - r.left) / r.width) * 100;
                const y = ((e.clientY - r.top) / r.height) * 100;
                card.style.setProperty('--mx', x + '%');
                card.style.setProperty('--my', y + '%');
            });
        });
    };

    // ---------- 5. Animated counters for stats (if numeric) ----------
    const initCounters = () => {
        const stats = document.querySelectorAll('.stat-number');
        stats.forEach((el) => {
            const raw = (el.textContent || '').trim();
            const match = raw.match(/^(\d+)([+%kKM]?)$/);
            if (!match) return; // skip non-numeric (e.g. "-")
            const target = parseInt(match[1], 10);
            const suffix = match[2] || '';
            el.textContent = '0' + suffix;
            const io = new IntersectionObserver((entries) => {
                entries.forEach((entry) => {
                    if (entry.isIntersecting) {
                        const start = performance.now();
                        const dur = 1600;
                        const tick = (t) => {
                            const p = Math.min((t - start) / dur, 1);
                            const eased = 1 - Math.pow(1 - p, 3);
                            el.textContent = Math.round(target * eased) + suffix;
                            if (p < 1) requestAnimationFrame(tick);
                        };
                        requestAnimationFrame(tick);
                        io.unobserve(el);
                    }
                });
            }, { threshold: 0.5 });
            io.observe(el);
        });
    };

    // ---------- 6. Parallax-lite on hero phone ----------
    const initParallax = () => {
        if (prefersReducedMotion) return;
        const phone = document.querySelector('.phone-mockup');
        if (!phone) return;
        window.addEventListener('scroll', () => {
            const y = window.scrollY;
            if (y < 800) {
                phone.style.translate = `0 ${y * 0.08}px`;
            }
        }, { passive: true });
    };

    // ---------- 7. Nav bar scroll state (in case main.js missing) ----------
    const initNavScroll = () => {
        const nav = document.querySelector('.navbar');
        if (!nav) return;
        const onScroll = () => {
            if (window.scrollY > 24) nav.classList.add('scrolled');
            else nav.classList.remove('scrolled');
        };
        onScroll();
        window.addEventListener('scroll', onScroll, { passive: true });
    };

    // ---------- 8. Modal polish: body scroll lock + Escape close ----------
    const initModalPolish = () => {
        const selectors = ['.download-modal', '.tutorial-modal', '.success-message'];
        const isAnyOpen = () => selectors.some((s) => {
            const el = document.querySelector(s);
            return el && el.classList.contains('active');
        });
        const sync = () => {
            document.body.classList.toggle('modal-open', isAnyOpen());
        };

        // Watch class changes on modals (created lazily by main.js)
        const watch = (el) => {
            if (!el || el._observed) return;
            el._observed = true;
            new MutationObserver(sync).observe(el, { attributes: true, attributeFilter: ['class'] });
        };
        // Watch existing ones
        selectors.forEach((s) => document.querySelectorAll(s).forEach(watch));
        // Catch ones added later (download modal is created on demand)
        new MutationObserver((records) => {
            records.forEach((r) => {
                r.addedNodes.forEach((n) => {
                    if (n.nodeType === 1 && selectors.some((s) => n.matches && n.matches(s))) watch(n);
                });
            });
            sync();
        }).observe(document.body, { childList: true });

        // Escape closes any open modal
        document.addEventListener('keydown', (e) => {
            if (e.key !== 'Escape') return;
            if (typeof window.closeDownloadModal === 'function') {
                const m = document.getElementById('downloadModal');
                if (m && m.classList.contains('active')) window.closeDownloadModal();
            }
            const tm = document.getElementById('tutorialModal');
            if (tm && tm.classList.contains('active')) tm.classList.remove('active');
            const sm = document.getElementById('successMessage');
            if (sm && sm.classList.contains('active')) sm.classList.remove('active');
        });
    };

    // ---------- 8. Boot ----------
    const boot = () => {
        decorate();
        initReveal();
        initMagnetic();
        initSpotlight();
        initCounters();
        initParallax();
        initNavScroll();
        initModalPolish();
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot);
    } else {
        boot();
    }
})();
