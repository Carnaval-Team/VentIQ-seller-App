/* =========================================================
   INVENTTIA · Aurora background (PS3 XMB style)
   Layered sine waves on 2D canvas — cheap, smooth, looped.
   ========================================================= */

(function () {
    const REDUCE = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const ROOT = document.querySelector('[data-aurora]');
    if (!ROOT) return;

    // On reduced motion: keep the CSS gradient fallback only.
    if (REDUCE) return;

    const canvas = ROOT.querySelector('.v2-aurora-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d', { alpha: true });
    if (!ctx) return;

    const DPR = Math.min(window.devicePixelRatio || 1, 2);
    let W = 0, H = 0;

    function resize() {
        W = canvas.clientWidth;
        H = canvas.clientHeight;
        canvas.width = Math.floor(W * DPR);
        canvas.height = Math.floor(H * DPR);
        ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    }
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);

    // PS3 XMB-style "wave bands": 5 stacked sine waves with shifted phases & colors.
    // Drawn additively so colors mix into iridescent ribbons.
    const bands = [
        { color: 'rgba(124, 58, 237, 0.55)', amp: 0.18, freq: 0.0022, speed: 0.22, phase: 0.0,  yBase: 0.42, thick: 220 },
        { color: 'rgba( 79, 70, 229, 0.50)', amp: 0.22, freq: 0.0018, speed: 0.18, phase: 1.5,  yBase: 0.55, thick: 260 },
        { color: 'rgba( 37, 99, 235, 0.42)', amp: 0.16, freq: 0.0026, speed: 0.28, phase: 3.0,  yBase: 0.32, thick: 200 },
        { color: 'rgba( 34, 211, 238, 0.38)', amp: 0.20, freq: 0.0020, speed: 0.16, phase: 4.5,  yBase: 0.62, thick: 240 },
        { color: 'rgba(236,  72, 153, 0.30)', amp: 0.14, freq: 0.0024, speed: 0.24, phase: 5.8,  yBase: 0.48, thick: 180 },
    ];

    let t = 0;
    let last = performance.now();
    let running = true;

    // Pause when tab hidden
    document.addEventListener('visibilitychange', () => {
        running = !document.hidden;
        if (running) { last = performance.now(); requestAnimationFrame(loop); }
    });

    function drawBand(band, time) {
        const y0 = H * band.yBase;
        const step = 8; // pixel step along x — coarse enough to be fast, smooth via curves
        ctx.beginPath();
        ctx.moveTo(-step, H + 10);

        // Trace a wave path across the screen
        for (let x = -step; x <= W + step; x += step) {
            const wave =
                Math.sin(x * band.freq + time * band.speed + band.phase) * band.amp * H +
                Math.sin(x * band.freq * 0.5 + time * band.speed * 1.3 + band.phase * 0.7) * (band.amp * H * 0.45);
            const y = y0 + wave;
            ctx.lineTo(x, y);
        }

        // Close the ribbon: extend down and back
        ctx.lineTo(W + step, H + 10);
        ctx.closePath();

        // Gradient fill — color band has soft fade top + bottom
        const grad = ctx.createLinearGradient(0, y0 - band.thick, 0, y0 + band.thick);
        grad.addColorStop(0.0, 'rgba(255,255,255,0)');
        grad.addColorStop(0.5, band.color);
        grad.addColorStop(1.0, 'rgba(255,255,255,0)');
        ctx.fillStyle = grad;
        ctx.fill();
    }

    function loop(now) {
        if (!running) return;
        const dt = (now - last) / 1000;
        last = now;
        t += dt;

        // Clear with full transparency
        ctx.clearRect(0, 0, W, H);

        // Additive blending: ribbons overlap into iridescent color
        ctx.globalCompositeOperation = 'lighter';

        bands.forEach((b) => drawBand(b, t));

        ctx.globalCompositeOperation = 'source-over';

        requestAnimationFrame(loop);
    }

    requestAnimationFrame((now) => { last = now; loop(now); });
})();
